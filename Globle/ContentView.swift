import SwiftUI
import CoreLocation

struct ContentView: View {
    @State private var geoJson: GeoJson? = nil
    @State private var highlightedCountry: String = ""
    @State private var searchText: String = ""
    @State private var secretCountry: String = ""
    @State private var gameWon: Bool = false
    @State private var attempts: Int = 0
    @State private var distance: Double? = nil
    @State private var showingAlert = false
    @State private var gameOver = false
    @State private var predictions: [String] = []

    @State private var showSearchSheet = false // For controlling sheet visibility
    @State private var sheetHeight: CGFloat = UIScreen.main.bounds.height * 0.25 // Initial height of the sheet

    var body: some View {
        ZStack {
            // Background and Globe
            Color.black.ignoresSafeArea()
            
            if let geoJson = geoJson {
                Globe3DView(geoJson: geoJson, highlightedCountry: highlightedCountry)
                    .ignoresSafeArea()
            }
            
            // Top overlay for attempts and distance
            VStack {
                HStack {
                    Text("Attempts: \(attempts)")
                        .foregroundColor(.white)
                    Spacer()
                    if let distance = distance {
                        Text("Distance: \(Int(distance)) km")
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.5))
                
                Spacer()
            }
            
            // Bottom sheet (search section)
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    // Handle
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.gray)
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                    
                    // Search bar and button
                    HStack {
                        TextField("Enter country name", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .frame(height:40)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray, lineWidth: 1)
                            )
                            .padding(.horizontal)
                        
                        Button("Search") {
                            performSearch()
                        }
                        .padding(.trailing)
                        .foregroundStyle(.white)
                        .disabled(searchText.isEmpty)
                    }
                    .padding(.vertical)
                    
                    // Predictions
                    if !predictions.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading) {
                                ForEach(predictions, id: \ .self) { prediction in
                                    Button(action: {
                                        searchText = prediction
                                        performSearch()
                                    }) {
                                        Text(prediction)
                                            .foregroundColor(.primary)
                                            .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 100)
                    }
                }
                .background(.black)
                .cornerRadius(15)
                .frame(height: sheetHeight) // Use the dynamic height here
                .offset(y: showSearchSheet ? 0 : UIScreen.main.bounds.height) // Adjust position
                .animation(.spring(), value: showSearchSheet) // Animation to slide the sheet
            }
        }
        .onAppear {
            loadGeoJson()
            selectRandomCountry()
            showSearchSheet = true // Show sheet when view appears
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
    
    private func performSearch() {
        highlightedCountry = searchText.trimmed().capitalized
        attempts += 1
        if highlightedCountry == secretCountry {
            gameWon = true
            showingAlert = true
        }
        calculateDistance()
        updatePredictions()
        searchText = "" // TextField'i sıfırla
        print("Search triggered for: \(highlightedCountry)")
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
    
    private func updatePredictions() {
        predictions = geoJson?.features
            .compactMap { $0.countryName }
            .filter { $0.lowercased().contains(searchText.lowercased()) }
            .prefix(5)
            .map { $0.capitalized } ?? []
    }
    
    private func restartGame() {
        selectRandomCountry()
        attempts = 0
        gameWon = false
        gameOver = false
        highlightedCountry = ""
        distance = nil
        searchText = ""
        predictions = []
    }
}

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

extension String {
    func trimmed() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
