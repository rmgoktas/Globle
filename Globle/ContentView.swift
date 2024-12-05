import SwiftUI
import CoreLocation

// MARK: - GeoJSON Structs
struct GeoJson: Codable {
    let type: String
    let features: [GeoJsonFeature]
}

struct PropertyValues: Codable {
    let scalerank: Double?
    let featurecla: String?
    let labelrank: Double?
    let sovereignt: String?
    let name: String?
}

struct GeoJsonFeature: Codable, Identifiable {
    var id: String {
        properties.name ?? UUID().uuidString
    }
    
    let type: String
    let properties: PropertyValues
    let geometry: GeoJsonGeometry
    
    var countryName: String? {
        return properties.name
    }
    
    var center: CLLocationCoordinate2D? {
        switch geometry.type {
        case "Polygon":
            return calculatePolygonCenter(geometry.coordinates.polygon ?? [])
        case "MultiPolygon":
            return calculateMultiPolygonCenter(geometry.coordinates.multiPolygon ?? [])
        default:
            return nil
        }
    }
    
    private func calculatePolygonCenter(_ coordinates: [[[Double]]]) -> CLLocationCoordinate2D? {
        guard let firstPolygon = coordinates.first else { return nil }
        let latitudes = firstPolygon.map { $0[1] }
        let longitudes = firstPolygon.map { $0[0] }
        let centerLatitude = latitudes.reduce(0.0, +) / Double(latitudes.count)
        let centerLongitude = longitudes.reduce(0.0, +) / Double(longitudes.count)
        return CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }
    
    private func calculateMultiPolygonCenter(_ coordinates: [[[[Double]]]]) -> CLLocationCoordinate2D? {
        let centers = coordinates.compactMap { calculatePolygonCenter($0) }
        let latitudes = centers.map { $0.latitude }
        let longitudes = centers.map { $0.longitude }
        let centerLatitude = latitudes.reduce(0.0, +) / Double(latitudes.count)
        let centerLongitude = longitudes.reduce(0.0, +) / Double(longitudes.count)
        return CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }
}

struct GeoJsonGeometry: Codable {
    let type: String
    let coordinates: GeoJsonCoordinates
}

struct GeoJsonCoordinates: Codable {
    var polygon: [[[Double]]]?
    var multiPolygon: [[[[Double]]]]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let polygon = try? container.decode([[[Double]]].self) {
            self.polygon = polygon
            return
        }
        if let multiPolygon = try? container.decode([[[[Double]]]].self) {
            self.multiPolygon = multiPolygon
            return
        }
        throw DecodingError.valueNotFound(Self.self, .init(codingPath: [], debugDescription: ""))
    }
}

struct ContentView: View {
    @State private var geoJson: GeoJson? = nil
    @State private var highlightedCountry: String = ""
    @State private var searchText: String = ""
    @State private var showGlobe: Bool = false
    @State private var secretCountry: String = ""
    @State private var gameWon: Bool = false
    @State private var attempts: Int = 0
    @State private var distance: Double? = nil
    @State private var showingAlert = false
    @State private var gameOver = false
    
    // State variables for zoom and pan
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        VStack {
            HStack {
                TextField("Enter country name", text: $searchText)
                    .padding()
                    .foregroundStyle(.black)
                    .background(Color.white) // Arka plan rengi beyaz
                    .cornerRadius(8) // Kenarları yuvarlatılmış bir görünüm için
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, lineWidth: 0.5) // Gri çerçeve
                    )
                    .frame(maxWidth: .infinity) // Enine genişliği artırmak için
                    .padding()

                Button(action: {
                    highlightedCountry = searchText.trimmed().capitalized
                    attempts += 1
                    if highlightedCountry == secretCountry {
                        gameWon = true
                        showingAlert = true
                    }
                    calculateDistance()
                    zoomToCountry(highlightedCountry)
                    print("Search triggered for: \(highlightedCountry)")
                    searchText = ""
                })
                {
                    Text("Guess")
                        .padding()
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding()
                
            }
            
            if gameWon && !gameOver {
                Text("Congratulations! You found the secret country in \(attempts) attempts!")
                    .foregroundColor(.green)
                    .padding()
            } else if !gameOver {
                Text("Attempts: \(attempts)")
                    .foregroundColor(.black)
                    .padding()
            }
            
            if let distance = distance {
                Text("Distance to secret country: \(Int(distance)) km")
                    .foregroundColor(.black)
                    .padding()
            }
            
            Toggle("Show 3D Globe", isOn: $showGlobe)
                .foregroundColor(.black)
                .padding()
            
            if showGlobe {
                if let geoJson = geoJson {
                    Globe3DView(geoJson: geoJson, highlightedCountry: highlightedCountry)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    Text("Loading 3D Globe...")
                }
            } else {
                VStack {
                    GeometryReader { geometry in
                        if let geoJson = geoJson {
                            ZStack {
                                ForEach(geoJson.features, id: \.id) { feature in
                                    if let polygons = feature.geometry.coordinates.polygon, feature.geometry.type == "Polygon" {
                                        renderPolygons(polygons, feature: feature, geometry: geometry)
                                            .animation(.easeInOut(duration: 0.5), value: highlightedCountry)
                                    } else if let multiPolygons = feature.geometry.coordinates.multiPolygon, feature.geometry.type == "MultiPolygon" {
                                        renderMultiPolygons(multiPolygons, feature: feature, geometry: geometry)
                                            .animation(.easeInOut(duration: 0.5), value: highlightedCountry)
                                    }
                                }
                            }
                        }
                    }
                    .background(Color.white)
                    .clipped()
                }
            }
        }
        .onAppear {
            loadGeoJson()
            selectRandomCountry()
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Congratulations!"),
                message: Text("You found the secret country in \(attempts) attempts! Do you want to play again?"),
                primaryButton: .default(Text("Yes")) {
                    restartGame()
                },
                secondaryButton: .cancel(Text("No")) {
                    gameOver = true
                }
            )
        }
    }
    
    private func renderPolygons(_ polygons: [[[Double]]], feature: GeoJsonFeature, geometry: GeometryProxy) -> some View {
        Group {
            ForEach(polygons, id: \.self) { polygon in
                PolygonShape(coordinates: polygon, size: geometry.size)
                    .fill(getCountryColor(for: feature.countryName))
                    .overlay(
                        PolygonShape(coordinates: polygon, size: geometry.size)
                            .stroke(Color.black, lineWidth: 0.5)
                    )
            }
        }
    }
    
    private func renderMultiPolygons(_ multiPolygons: [[[[Double]]]], feature: GeoJsonFeature, geometry: GeometryProxy) -> some View {
        Group {
            ForEach(multiPolygons, id: \.self) { multiPolygon in
                ForEach(multiPolygon, id: \.self) { polygon in
                    PolygonShape(coordinates: polygon, size: geometry.size)
                        .fill(getCountryColor(for: feature.countryName))
                        .overlay(
                            PolygonShape(coordinates: polygon, size: geometry.size)
                                .stroke(Color.black, lineWidth: 0.5)
                        )
                }
            }
        }
    }
    
    private func loadGeoJson() {
        if let url = Bundle.main.url(forResource: "geo", withExtension: "geojson") {
            do {
                let data = try Data(contentsOf: url)
                geoJson = try JSONDecoder().decode(GeoJson.self, from: data)
                print("GeoJSON file loaded successfully")
            } catch {
                print("Failed to load GeoJSON data: \(error)")
            }
        } else {
            print("GeoJSON file not found!")
        }
    }
    
    private func selectRandomCountry() {
        if let randomCountry = geoJson?.features.compactMap({ $0.countryName }).randomElement() {
            secretCountry = randomCountry.trimmed().capitalized
            print("Secret country: \(secretCountry)")
        }
    }
    
    private func getCountryColor(for countryName: String?) -> Color {
        guard let name = countryName?.trimmed().capitalized else {
            return Color.blue.opacity(0.3)
        }
        
        if name == secretCountry && gameWon {
            return Color.green
        } else if name == highlightedCountry {
            if let distance = distance, !distance.isNaN {
                // Mesafeye göre renk değişimi
                let normalizedDistance = min(max(distance / 10000, 0), 1)
                return Color(red: 1, green: normalizedDistance, blue: 0)
            }
            return Color.red
        } else {
            return Color.blue.opacity(0.3)
        }
    }
    
    private func calculateDistance() {
        guard let guessedCountry = geoJson?.features.first(where: { $0.countryName?.trimmed().capitalized == highlightedCountry }),
              let secretCountryFeature = geoJson?.features.first(where: { $0.countryName?.trimmed().capitalized == secretCountry }),
              let guessedCenter = guessedCountry.center,
              let secretCenter = secretCountryFeature.center else {
            distance = nil
            return
        }
        
        distance = haversineDistance(from: guessedCenter, to: secretCenter)
    }
    
    private func haversineDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6371.0 // Earth's radius in kilometers
        
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        
        let dLat = lat2 - lat1
        let dLon = lon2 - lon1
        
        let a = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(max(0, min(1, a))), sqrt(max(0, min(1, 1-a))))
        
        let distance = earthRadius * c
        return distance.isNaN ? 0 : distance
    }
    
    private func zoomToCountry(_ countryName: String) {
        guard let country = geoJson?.features.first(where: { $0.countryName?.trimmed().capitalized == countryName }),
              let center = country.center,
              !center.latitude.isNaN && !center.longitude.isNaN else {
            return
        }
        
        // Zoom animasyonu
        withAnimation(.spring()) {
            scale = 2.0
            offset = CGSize(width: -center.longitude * 2, height: center.latitude * 2)
        }
        
        // 2 saniye sonra zoom'u sıfırla
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring()) {
                scale = 1.0
                offset = .zero
            }
        }
    }
    
    private func restartGame() {
        selectRandomCountry()
        attempts = 0
        gameWon = false
        gameOver = false
        highlightedCountry = ""
        distance = nil
        scale = 1.0
        offset = .zero
        lastScale = 1.0
        lastOffset = .zero
    }
}

extension String {
    func trimmed() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PolygonShape: Shape {
    let coordinates: [[Double]]
    let size: CGSize
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard coordinates.first != nil else { return path }
        
        let points = coordinates.map { coord -> CGPoint in
            let x = (coord[0] + 180) * (rect.width / 360)
            let latitudeRadians = coord[1] * .pi / 180
            let mercatorProjection = log(tan((.pi / 4) + (latitudeRadians / 2)))
            let y = rect.height / 2 - (rect.width * mercatorProjection / (2 * .pi))
            
            return CGPoint(x: x, y: y)
        }
        
        path.move(to: points[0])
        points.forEach { path.addLine(to: $0) }
        path.closeSubpath()
        
        return path
    }
}


