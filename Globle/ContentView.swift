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
    let name: String? // This is where we get the name of the country
}

struct GeoJsonFeature: Codable, Identifiable {
    var id: String {
        properties.name ?? UUID().uuidString  // Using name as ID
    }
    
    let type: String
    let properties: PropertyValues
    let geometry: GeoJsonGeometry
    
    // Computed property for country name
    var countryName: String? {
        return properties.name  // Access the 'name' from the 'properties' struct
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
    
    var body: some View {
        VStack {
            HStack {
                TextField("Enter country name", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                Button(action: {
                    highlightedCountry = searchText.trimmed().capitalized
                    print("Search triggered for: \(highlightedCountry)")
                }) {
                    Text("Search")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            
            Toggle("Show 3D Globe", isOn: $showGlobe)
                .padding()
            
            if showGlobe {
                if let geoJson = geoJson {
                    Globe3DView(geoJson: geoJson, highlightedCountry: highlightedCountry)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    Text("Loading 3D Globe...")
                }
            } else {
                GeometryReader { geometry in
                    if let geoJson = geoJson {
                        ZStack {
                            ForEach(geoJson.features, id: \.id) { feature in
                                if let polygons = feature.geometry.coordinates.polygon, feature.geometry.type == "Polygon" {
                                    renderPolygons(polygons, feature: feature, geometry: geometry)
                                } else if let multiPolygons = feature.geometry.coordinates.multiPolygon, feature.geometry.type == "MultiPolygon" {
                                    renderMultiPolygons(multiPolygons, feature: feature, geometry: geometry)
                                }
                            }
                        }
                    }
                }
                .background(Color.white)
            }
        }
        .onAppear {
            loadGeoJson()
        }
    }
    
    private func renderPolygons(_ polygons: [[[Double]]], feature: GeoJsonFeature, geometry: GeometryProxy) -> some View {
        Group {
            ForEach(polygons, id: \.self) { polygon in
                PolygonShape(coordinates: polygon, size: geometry.size)
                    .fill(feature.countryName?.trimmed().capitalized == highlightedCountry ? Color.red : Color.blue.opacity(0.3))
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
                        .fill(feature.countryName?.trimmed().capitalized == highlightedCountry ? Color.red : Color.blue.opacity(0.3))
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
        guard let first = coordinates.first else { return path }
        
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


