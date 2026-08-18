import Foundation
import Combine

@MainActor
final class osrsRealmMapStore: ObservableObject {
    @Published private(set) var manifest: osrsRealmMapManifest?
    @Published var activeRealmID: String = "surface-gielinor"
    @Published var activePlane: Int = 0
    @Published var query: String = ""
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let bundle: Bundle

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.bundle = bundle
        self.defaults = defaults
        load()
    }

    var activeRealm: osrsRealmMapRecord? {
        manifest?.realm(id: activeRealmID) ?? manifest?.surface
    }

    var filteredRealms: [osrsRealmMapRecord] {
        let realms = manifest?.canonicalSelectorRealms.sorted {
            if $0.isSurface != $1.isSurface { return $0.isSurface }
            return $0.canonicalName.localizedStandardCompare($1.canonicalName) == .orderedAscending
        } ?? []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        return trimmed.isEmpty ? realms : realms.filter { $0.searchableText.contains(trimmed) }
    }

    func select(realm: osrsRealmMapRecord) {
        activeRealmID = realm.id
        activePlane = realm.defaultPlane
        defaults.set(realm.id, forKey: Self.realmKey)
        defaults.set(activePlane, forKey: Self.planeKey)
    }

    func select(plane: Int) {
        guard activeRealm?.planes.contains(plane) == true else { return }
        activePlane = plane
        defaults.set(plane, forKey: Self.planeKey)
    }

    func assetURL(for asset: osrsRealmMapAsset) -> URL? {
        bundle.resourceURL?
            .appendingPathComponent("UndergroundRealms", isDirectory: true)
            .appendingPathComponent(asset.mbtilesPath)
    }

    func camera(for realm: osrsRealmMapRecord) -> osrsRealmPersistedCamera? {
        guard let data = defaults.data(forKey: cameraKey(realmID: realm.id)),
              let camera = try? JSONDecoder().decode(osrsRealmPersistedCamera.self, from: data),
              camera.geometryIdentity == realm.cameraGeometryIdentity else { return nil }
        return camera
    }

    func saveCamera(_ camera: osrsRealmPersistedCamera, realmID: String) {
        guard let data = try? JSONEncoder().encode(camera) else { return }
        defaults.set(data, forKey: cameraKey(realmID: realmID))
    }

    private func load() {
        do {
            if ProcessInfo.processInfo.arguments.contains("-resetRealmMapState") {
                resetPersistedMapState()
            }
            let loaded = try osrsRealmMapManifest.load(bundle: bundle)
            manifest = loaded
            let savedRealm = defaults.string(forKey: Self.realmKey)
            let realm = savedRealm.flatMap(loaded.realm(id:)) ?? loaded.surface ?? loaded.realms.first
            guard let realm else { throw osrsRealmMapError.missingManifest }
            activeRealmID = realm.id
            let savedPlane = defaults.object(forKey: Self.planeKey) as? Int
            activePlane = savedPlane.flatMap { realm.planes.contains($0) ? $0 : nil }
                ?? realm.defaultPlane
        } catch {
            errorMessage = "The map could not load its offline assets."
        }
    }

    private func resetPersistedMapState() {
        for key in defaults.dictionaryRepresentation().keys where
            key == Self.realmKey || key == Self.planeKey || key.hasPrefix(Self.cameraPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func cameraKey(realmID: String) -> String {
        "\(Self.cameraPrefix)realm:\(realmID)"
    }

    private static let realmKey = "osrs.realm-map.realm"
    private static let planeKey = "osrs.realm-map.plane"
    private static let cameraPrefix = "osrs.realm-map.camera:"
}
