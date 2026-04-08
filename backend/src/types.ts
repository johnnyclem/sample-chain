/** Shared TypeScript types for SampleChain backend */

export interface Sample {
  id: number;
  token_id: number;
  creator_address: string;
  ipfs_cid: string;
  title: string;
  description: string | null;
  bpm: number | null;
  musical_key: string | null;
  sample_type: SampleType;
  license_tier: LicenseTier;
  price_wei: string;
  edition_count: number;
  edition_limit: number | null;
  genre: string | null;
  instrument_type: string | null;
  waveform_data: number[] | null;
  created_at: Date;
  updated_at: Date;
}

export interface Creator {
  address: string;
  display_name: string | null;
  bio: string | null;
  avatar_url: string | null;
  created_at: Date;
}

export interface Sale {
  id: number;
  token_id: number;
  buyer_address: string;
  seller_address: string;
  price_wei: string;
  tx_hash: string;
  created_at: Date;
}

export interface Favorite {
  user_address: string;
  token_id: number;
  created_at: Date;
}

export type SampleType = 'one-shot' | 'loop' | 'stem' | 'full-track';
export type LicenseTier = 'free' | 'basic' | 'premium' | 'exclusive';

export interface PaginationParams {
  page: number;
  limit: number;
}

export interface SampleFilterParams extends PaginationParams {
  genre?: string;
  instrument_type?: string;
  bpm_min?: number;
  bpm_max?: number;
  key?: string;
  sample_type?: SampleType;
  license_tier?: LicenseTier;
  creator?: string;
  sort_by?: 'created_at' | 'price' | 'title' | 'bpm';
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
  };
}

export interface JwtPayload {
  address: string;
  iat: number;
}

export interface UploadJobData {
  filePath: string;
  originalName: string;
  mimeType: string;
  creatorAddress: string;
  title: string;
  description?: string;
  bpm?: number;
  musicalKey?: string;
  sampleType: SampleType;
  licenseTier: LicenseTier;
  priceWei: string;
  editionLimit?: number;
  genre?: string;
  instrumentType?: string;
}

export interface TranscodeResult {
  waveformData: number[];
  durationSeconds: number;
  format: string;
  sampleRate: number;
  channels: number;
}
