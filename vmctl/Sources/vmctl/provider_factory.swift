import Foundation

/// Struct used to create a concrete instance of a provider.
struct ProviderFactory {
  /// Create a concrete instance of a provider given a string representation of the class name.
  public static func providerFromString(classString: String, config: ProviderConfig) -> Provider? {
    if let aClass = NSClassFromString("\(classString)") as? Provider.Type {
      let provider = providerFromType(klass: aClass, config: config)

      return provider
    }

    return Optional.none
  }

  private static func providerFromType<T>(klass: T.Type, config: ProviderConfig) -> T where T: Provider {
    klass.init(config: config)
  }
}
