import Foundation
import ImageIO

/// Serial, off-main-thread decoding also coalesces simultaneous requests for one image.
actor EnvironmentImageStore {
  static let shared = EnvironmentImageStore()
  private let cache = NSCache<NSString, CGImage>()

  init() {
    cache.totalCostLimit = 96 * 1024 * 1024
    cache.countLimit = 12
  }

  func image(at url: URL, maxPixelSize: Int) -> CGImage? {
    let limit = max(1, min(4096, maxPixelSize))
    let key = "\(url.path):\(limit)" as NSString
    if let image = cache.object(forKey: key) { return image }
    guard
      let source = CGImageSourceCreateWithURL(
        url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceShouldCacheImmediately: true,
          kCGImageSourceThumbnailMaxPixelSize: limit,
        ] as CFDictionary)
    else { return nil }
    cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
    return image
  }
}
