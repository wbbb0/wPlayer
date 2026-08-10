export class ArtworkSourceIdentityPolicy {
  static readonly ALGORITHM: string = 'xxh3-128';
  static readonly PREFIX: string = `${ArtworkSourceIdentityPolicy.ALGORITHM}:`;
  private static readonly DIGEST_LENGTH: number = 32;
  static readonly IDENTITY_LENGTH: number =
    ArtworkSourceIdentityPolicy.PREFIX.length + ArtworkSourceIdentityPolicy.DIGEST_LENGTH;
  private static readonly LEGACY_SHA256_LENGTH: number = 64;

  static fromCurrentDigest(digest: string): string {
    const normalized = digest.toLowerCase();
    if (!ArtworkSourceIdentityPolicy.isHex(normalized,
      ArtworkSourceIdentityPolicy.DIGEST_LENGTH)) {
      throw new Error('Invalid XXH3-128 artwork digest');
    }
    return `${ArtworkSourceIdentityPolicy.PREFIX}${normalized}`;
  }

  static isCurrent(identity: string): boolean {
    if (!identity.startsWith(ArtworkSourceIdentityPolicy.PREFIX)) {
      return false;
    }
    return ArtworkSourceIdentityPolicy.isHex(
      identity.substring(ArtworkSourceIdentityPolicy.PREFIX.length),
      ArtworkSourceIdentityPolicy.DIGEST_LENGTH
    );
  }

  static isLegacySha256(identity: string): boolean {
    return ArtworkSourceIdentityPolicy.isHex(
      identity.toLowerCase(), ArtworkSourceIdentityPolicy.LEGACY_SHA256_LENGTH
    );
  }

  static currentDigest(identity: string): string {
    if (!ArtworkSourceIdentityPolicy.isCurrent(identity)) {
      throw new Error('Artwork source identity is not current');
    }
    return identity.substring(ArtworkSourceIdentityPolicy.PREFIX.length);
  }

  static cacheKey(identity: string, encodingVersion: number, variant: string): string {
    return `${identity}:v${encodingVersion}:${variant}`;
  }

  private static isHex(value: string, expectedLength: number): boolean {
    if (value.length !== expectedLength) {
      return false;
    }
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      const digit = code >= 48 && code <= 57;
      const lowerHex = code >= 97 && code <= 102;
      if (!digit && !lowerHex) {
        return false;
      }
    }
    return true;
  }
}
