import SwiftUI
import SceneKit

struct Globe3DView: UIViewRepresentable {
    var geoJson: GeoJson
    var highlightedCountry: String

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = SCNScene()
        sceneView.backgroundColor = .black
        sceneView.allowsCameraControl = true

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 15)
        sceneView.scene?.rootNode.addChildNode(cameraNode)

        let globeNode = createGlobe()
        sceneView.scene?.rootNode.addChildNode(globeNode)

        addCountries(to: globeNode)

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        updateHighlightedCountry(in: uiView)
    }

    private func createGlobe() -> SCNNode {
        let sphere = SCNSphere(radius: 5)
        let material = SCNMaterial()
        material.diffuse.contents = UIImage(named: "earth.jpg") // Earth texture
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeTranslation(-0.26, 0, 0) // Adjust texture offset
        material.specular.contents = UIColor.white
        material.shininess = 0.1
        material.lightingModel = .blinn
        sphere.materials = [material]

        let globeNode = SCNNode(geometry: sphere)
        return globeNode
    }

    private func addCountries(to globeNode: SCNNode) {
        let countriesNode = SCNNode()

        for feature in geoJson.features {
            if let polygons = feature.geometry.coordinates.polygon {
                addPolygons(polygons, to: countriesNode, for: feature)
            } else if let multiPolygons = feature.geometry.coordinates.multiPolygon {
                for polygons in multiPolygons {
                    addPolygons(polygons, to: countriesNode, for: feature)
                }
            }
        }

        globeNode.addChildNode(countriesNode)
    }

    private func addPolygons(_ polygons: [[[Double]]], to node: SCNNode, for feature: GeoJsonFeature) {
        for polygon in polygons {
            let points = polygon.compactMap { coord -> SCNVector3? in
                guard coord.count >= 2 else { return nil }
                return projectToSphere(latitude: coord[1], longitude: coord[0])
            }

            guard points.count > 2 else { continue }

            // Create line geometry for borders
            let geometry = SCNGeometry.lineGeometry(points: points)
            let borderMaterial = SCNMaterial()
            borderMaterial.diffuse.contents = UIColor.black
            borderMaterial.transparency = 0.8
            geometry.materials = [borderMaterial]

            let countryNode = SCNNode(geometry: geometry)
            countryNode.name = feature.countryName

            // Create fill geometry for highlighted state
            if let fillGeometry = createFillGeometry(from: points) {
                let fillMaterial = SCNMaterial()
                fillMaterial.diffuse.contents = UIColor.clear
                fillMaterial.isDoubleSided = true
                fillMaterial.cullMode = .back
                fillGeometry.materials = [fillMaterial]

                let fillNode = SCNNode(geometry: fillGeometry)
                fillNode.name = "\(feature.countryName ?? "")-fill"

                node.addChildNode(fillNode)
            }

            node.addChildNode(countryNode)
        }
    }

    private func createFillGeometry(from points: [SCNVector3]) -> SCNGeometry? {
        guard points.count >= 3 else { return nil }

        // Create a denser set of points for large areas
        let densePoints = subdivideLargePolygon(points)

        // Create vertices and normals
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []

        // Calculate centroid
        var centerX: Float = 0, centerY: Float = 0, centerZ: Float = 0
        for point in densePoints {
            centerX += point.x
            centerY += point.y
            centerZ += point.z
        }
        let count = Float(densePoints.count)
        let centroid = SCNVector3(centerX / count, centerY / count, centerZ / count)

        // Project centroid to sphere surface
        let length = sqrt(centroid.x * centroid.x + centroid.y * centroid.y + centroid.z * centroid.z)
        let normalizedCentroid = SCNVector3(
            centroid.x / length * 5.02,
            centroid.y / length * 5.02,
            centroid.z / length * 5.02
        )

        // Add centroid as first vertex
        vertices.append(normalizedCentroid)
        normals.append(normalizeVector(normalizedCentroid))

        // Add boundary points
        for point in densePoints {
            vertices.append(point)
            normals.append(normalizeVector(point))
        }

        // Create triangles
        for i in 0..<densePoints.count {
            indices.append(0) // Centroid
            indices.append(Int32(i + 1))
            indices.append(Int32((i + 1) % densePoints.count + 1))
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }

    private func subdivideLargePolygon(_ points: [SCNVector3]) -> [SCNVector3] {
        var result: [SCNVector3] = []

        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]

            // Calculate distance between points
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let dz = p2.z - p1.z
            let distance = sqrt(dx * dx + dy * dy + dz * dz)

            // Add first point
            result.append(p1)

            // Subdivide if distance is large
            if distance > 0.5 { // Adjust this threshold as needed
                let subdivisions = Int(distance * 10) // Adjust multiplication factor as needed
                for j in 1..<subdivisions {
                    let t = Float(j) / Float(subdivisions)
                    let x = p1.x + dx * t
                    let y = p1.y + dy * t
                    let z = p1.z + dz * t

                    // Project intermediate point to sphere surface
                    let length = sqrt(x * x + y * y + z * z)
                    let point = SCNVector3(
                        x / length * 5.02,
                        y / length * 5.02,
                        z / length * 5.02
                    )
                    result.append(point)
                }
            }
        }

        return result
    }

    private func normalizeVector(_ v: SCNVector3) -> SCNVector3 {
        let length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        return SCNVector3(v.x / length, v.y / length, v.z / length)
    }

    private func projectToSphere(latitude: Double, longitude: Double) -> SCNVector3? {
        let radius: Float = 5.02
        let phi = Float((90 - latitude) * .pi / 180)
        let theta = Float((longitude + 180) * .pi / 180)

        guard !phi.isNaN && !theta.isNaN else { return nil }

        let x = -radius * sin(phi) * cos(theta)
        let y = radius * cos(phi)
        let z = radius * sin(phi) * sin(theta)

        guard !x.isNaN && !y.isNaN && !z.isNaN else { return nil }

        return SCNVector3(x, y, z)
    }

    private func updateHighlightedCountry(in sceneView: SCNView) {
        sceneView.scene?.rootNode.enumerateChildNodes { (node, _) in
            if node.name?.contains("-fill") == true {
                let countryName = node.name?.replacingOccurrences(of: "-fill", with: "")
                if countryName == highlightedCountry {
                    node.geometry?.firstMaterial?.diffuse.contents = UIColor.red
                    node.geometry?.firstMaterial?.transparency = 0.8
                } else {
                    node.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
                }
            }
        }
    }
}

extension SCNGeometry {
    static func lineGeometry(points: [SCNVector3]) -> SCNGeometry {
        let source = SCNGeometrySource(vertices: points)

        var indices = [Int32]()
        for i in 0..<points.count {
            indices.append(Int32(i))
            indices.append(Int32((i + 1) % points.count))
        }

        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        return SCNGeometry(sources: [source], elements: [element])
    }
}

/* struct Globe3DView_Previews: PreviewProvider {
    static var previews: some View {
        Globe3DView(
            geoJson: GeoJson(type: "MultiPolygon", features: []), highlightedCountry: "Turkey"    )                     }}*/
