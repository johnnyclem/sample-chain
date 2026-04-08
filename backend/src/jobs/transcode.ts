import { Queue, Worker, type Job } from 'bullmq';
import IORedis from 'ioredis';
import { config } from '../config.js';
import type { TranscodeResult } from '../types.js';

/** Job data sent from the upload route */
interface TranscodeJobData {
  fileData: string; // base64-encoded audio file
  originalName: string;
  mimeType: string;
  creatorAddress: string;
  title: string;
  description?: string;
  bpm?: number;
  musicalKey?: string;
  sampleType: string;
  licenseTier: string;
  priceWei: string;
  editionLimit?: number;
  genre?: string;
  instrumentType?: string;
}

const connection = new IORedis(config.redisUrl, {
  maxRetriesPerRequest: null,
  lazyConnect: true,
});

export const transcodeQueue = new Queue<TranscodeJobData>('transcode', {
  connection,
  defaultJobOptions: {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 2000,
    },
    removeOnComplete: { count: 1000 },
    removeOnFail: { count: 5000 },
  },
});

/**
 * Generate waveform peak data from raw audio buffer.
 * Produces an array of normalized amplitude values (0-1).
 */
function generateWaveformPeaks(audioBuffer: Buffer, numPeaks: number = 200): number[] {
  // Simplified waveform generation: treat raw bytes as amplitude data
  // In production, this would use a proper audio decoder (e.g., ffmpeg, audiowaveform)
  const peaks: number[] = [];
  const samplesPerPeak = Math.max(1, Math.floor(audioBuffer.length / numPeaks));

  for (let i = 0; i < numPeaks; i++) {
    const start = i * samplesPerPeak;
    const end = Math.min(start + samplesPerPeak, audioBuffer.length);

    let max = 0;
    for (let j = start; j < end; j += 2) {
      // Read as 16-bit signed integer (little-endian)
      if (j + 1 < audioBuffer.length) {
        const sample = audioBuffer.readInt16LE(j);
        const abs = Math.abs(sample) / 32768;
        if (abs > max) max = abs;
      }
    }
    peaks.push(Math.round(max * 1000) / 1000);
  }

  return peaks;
}

/**
 * Validate audio format and duration.
 * Returns estimated duration based on file size and format assumptions.
 */
function validateAudio(
  buffer: Buffer,
  mimeType: string,
): { valid: boolean; error?: string; durationSeconds: number; format: string; sampleRate: number; channels: number } {
  const format = mimeType.includes('aiff') ? 'AIFF' : 'WAV';

  // Basic WAV header validation
  if (format === 'WAV') {
    if (buffer.length < 44) {
      return { valid: false, error: 'File too small to be a valid WAV', durationSeconds: 0, format, sampleRate: 0, channels: 0 };
    }
    const riff = buffer.subarray(0, 4).toString('ascii');
    if (riff !== 'RIFF') {
      return { valid: false, error: 'Invalid WAV header (missing RIFF)', durationSeconds: 0, format, sampleRate: 0, channels: 0 };
    }
    const channels = buffer.readUInt16LE(22);
    const sampleRate = buffer.readUInt32LE(24);
    const bitsPerSample = buffer.readUInt16LE(34);
    const dataSize = buffer.length - 44;
    const bytesPerSecond = sampleRate * channels * (bitsPerSample / 8);
    const durationSeconds = bytesPerSecond > 0 ? dataSize / bytesPerSecond : 0;

    if (durationSeconds > config.maxSampleDurationSeconds) {
      return {
        valid: false,
        error: `Audio duration ${durationSeconds.toFixed(1)}s exceeds maximum of ${config.maxSampleDurationSeconds}s`,
        durationSeconds,
        format,
        sampleRate,
        channels,
      };
    }

    return { valid: true, durationSeconds, format, sampleRate, channels };
  }

  // Basic AIFF header validation
  if (format === 'AIFF') {
    if (buffer.length < 54) {
      return { valid: false, error: 'File too small to be a valid AIFF', durationSeconds: 0, format, sampleRate: 0, channels: 0 };
    }
    const form = buffer.subarray(0, 4).toString('ascii');
    if (form !== 'FORM') {
      return { valid: false, error: 'Invalid AIFF header (missing FORM)', durationSeconds: 0, format, sampleRate: 0, channels: 0 };
    }

    // Rough estimate for AIFF (simplified)
    const estimatedDuration = buffer.length / (44100 * 2 * 2); // assume 44.1kHz, 16-bit, stereo
    return { valid: true, durationSeconds: estimatedDuration, format, sampleRate: 44100, channels: 2 };
  }

  return { valid: false, error: `Unsupported format: ${format}`, durationSeconds: 0, format, sampleRate: 0, channels: 0 };
}

/** Process a transcode job */
async function processTranscodeJob(job: Job<TranscodeJobData>): Promise<TranscodeResult> {
  const { fileData, mimeType } = job.data;

  await job.updateProgress(10);

  // Decode base64 file data
  const buffer = Buffer.from(fileData, 'base64');

  await job.updateProgress(20);

  // Validate audio format and duration
  const validation = validateAudio(buffer, mimeType);
  if (!validation.valid) {
    throw new Error(validation.error);
  }

  await job.updateProgress(50);

  // Generate waveform peaks
  const waveformData = generateWaveformPeaks(buffer);

  await job.updateProgress(80);

  // In production, this would also:
  // 1. Transcode to standard format if needed
  // 2. Upload to IPFS
  // 3. Create the on-chain token
  // 4. Store the sample record in the database

  await job.updateProgress(100);

  return {
    waveformData,
    durationSeconds: validation.durationSeconds,
    format: validation.format,
    sampleRate: validation.sampleRate,
    channels: validation.channels,
  };
}

/**
 * Create and start the transcode worker.
 * Call this from the main server startup.
 */
export function createTranscodeWorker(): Worker<TranscodeJobData, TranscodeResult> {
  const worker = new Worker<TranscodeJobData, TranscodeResult>(
    'transcode',
    processTranscodeJob,
    {
      connection: new IORedis(config.redisUrl, {
        maxRetriesPerRequest: null,
        lazyConnect: true,
      }),
      concurrency: 2,
    },
  );

  worker.on('completed', (job) => {
    console.log(`Transcode job ${job.id} completed`);
  });

  worker.on('failed', (job, err) => {
    console.error(`Transcode job ${job?.id} failed:`, err.message);
  });

  return worker;
}
