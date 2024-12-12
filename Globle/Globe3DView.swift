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
        material.diffuse.contentsTransform = SCNMatrix4MakeTranslation(-0.249, 0, 0) // Adjust texture offset
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
                addCountryLabel(for: feature, to: countriesNode)
                addPolygons(polygons, to: countriesNode, for: feature)
            } else if let multiPolygons = feature.geometry.coordinates.multiPolygon {
                addCountryLabel(for: feature, to: countriesNode)
                for polygons in multiPolygons {
                    addPolygons(polygons, to: countriesNode, for: feature)
                }
            }
        }

        globeNode.addChildNode(countriesNode)
    }

    private func addCountryLabel(for feature: GeoJsonFeature, to node: SCNNode) {
        guard let countryName = feature.countryName,
              let center = calculateCountryCenter(for: feature) else {
            return
        }

        let textGeometry = SCNText(string: countryName, extrusionDepth: 0)
        textGeometry.font = UIFont.systemFont(ofSize: 0.1) // Reduced font size
        textGeometry.flatness = 0.1

        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.005, 0.005, 0.005) // Adjusted scale
        textNode.position = center

        // Calculate the direction from the globe's center to the text
        let direction = SCNVector3(center.x, center.y, center.z)
        let normalizedDirection = normalize(direction)

        // Move the text slightly above the surface of the globe
        let offsetDistance: Float = 0.02
        textNode.position = SCNVector3(
            center.x + normalizedDirection.x * offsetDistance,
            center.y + normalizedDirection.y * offsetDistance,
            center.z + normalizedDirection.z * offsetDistance
        )

        // Rotate the text to face outward from the globe's center
        textNode.eulerAngles = SCNVector3(
            Float.pi / 2 - acos(normalizedDirection.y),
            atan2(normalizedDirection.x, normalizedDirection.z),
            0
        )

        node.addChildNode(textNode)
    }

    private func calculateCountryCenter(for feature: GeoJsonFeature) -> SCNVector3? {
        var totalLat: Double = 0
        var totalLon: Double = 0
        var count: Int = 0

        if let polygons = feature.geometry.coordinates.polygon {
            for polygon in polygons {
                for coord in polygon {
                    totalLat += coord[1]
                    totalLon += coord[0]
                    count += 1
                }
            }
        } else if let multiPolygons = feature.geometry.coordinates.multiPolygon {
            for polygons in multiPolygons {
                for polygon in polygons {
                    for coord in polygon {
                        totalLat += coord[1]
                        totalLon += coord[0]
                        count += 1
                    }
                }
            }
        }

        guard count > 0 else { return nil }

        let avgLat = totalLat / Double(count)
        let avgLon = totalLon / Double(count)

        return projectToSphere(latitude: avgLat, longitude: avgLon)
    }

    private func addPolygons(_ polygons: [[[Double]]], to node: SCNNode, for feature: GeoJsonFeature) {
        for polygon in polygons {
            let points = polygon.compactMap { coord -> SCNVector3? in
                guard coord.count >= 2 else { return nil }
                return projectToSphere(latitude: coord[1], longitude: coord[0])
            }

            guard points.count > 2 else { continue }

            // Create border geometry
            let borderGeometry = createBorderGeometry(from: points)
            let borderMaterial = SCNMaterial()
            borderMaterial.diffuse.contents = UIColor.red.withAlphaComponent(0.3)
            borderMaterial.isDoubleSided = true
            borderMaterial.transparency = 0.7
            borderMaterial.blendMode = .alpha
            borderMaterial.writesToDepthBuffer = true
            borderMaterial.readsFromDepthBuffer = true
            borderGeometry.materials = [borderMaterial]

            let borderNode = SCNNode(geometry: borderGeometry)
            borderNode.name = feature.countryName
            borderNode.renderingOrder = 2
            node.addChildNode(borderNode)
        }
    }

    private func createFillGeometry(from points: [SCNVector3]) -> SCNGeometry? {
        guard points.count >= 3 else { return nil }
        
        // Merkez noktayı hesapla
        var centerX: Float = 0, centerY: Float = 0, centerZ: Float = 0
        for point in points {
            centerX += point.x
            centerY += point.y
            centerZ += point.z
        }
        let count = Float(points.count)
        let centroid = SCNVector3(
            centerX / count,
            centerY / count,
            centerZ / count
        )
        
        // Merkezi küre yüzeyine yansıt
        let length = sqrt(centroid.x * centroid.x + centroid.y * centroid.y + centroid.z * centroid.z)
        let radius: Float = 5.02
        let normalizedCentroid = SCNVector3(
            centroid.x / length * radius,
            centroid.y / length * radius,
            centroid.z / length * radius
        )
        
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        
        // Recursive subdivision için yardımcı fonksiyon
        func subdivideTriangle(_ v1: SCNVector3, _ v2: SCNVector3, _ v3: SCNVector3, depth: Int) {
            if depth == 0 {
                let index = Int32(vertices.count)
                vertices.append(v1)
                vertices.append(v2)
                vertices.append(v3)
                
                let normal1 = normalizeVector(v1)
                let normal2 = normalizeVector(v2)
                let normal3 = normalizeVector(v3)
                normals.append(normal1)
                normals.append(normal2)
                normals.append(normal3)
                
                indices.append(index)
                indices.append(index + 1)
                indices.append(index + 2)
                return
            }
            
            // Kenar orta noktalarını hesapla ve küre yüzeyine yansıt
            func midpoint(_ p1: SCNVector3, _ p2: SCNVector3) -> SCNVector3 {
                let mid = SCNVector3(
                    (p1.x + p2.x) / 2,
                    (p1.y + p2.y) / 2,
                    (p1.z + p2.z) / 2
                )
                let len = sqrt(mid.x * mid.x + mid.y * mid.y + mid.z * mid.z)
                return SCNVector3(
                    mid.x / len * radius,
                    mid.y / len * radius,
                    mid.z / len * radius
                )
            }
            
            let v12 = midpoint(v1, v2)
            let v23 = midpoint(v2, v3)
            let v31 = midpoint(v3, v1)
            
            subdivideTriangle(v1, v12, v31, depth: depth - 1)
            subdivideTriangle(v2, v23, v12, depth: depth - 1)
            subdivideTriangle(v3, v31, v23, depth: depth - 1)
            subdivideTriangle(v12, v23, v31, depth: depth - 1)
        }
        
        // Poligonu üçgenlere böl
        let densePoints = subdivideLargePolygon(points)
        for i in 1..<(densePoints.count - 1) {
            let maxDepth = 2 // Recursive subdivision derinliği
            subdivideTriangle(normalizedCentroid, densePoints[i], densePoints[i + 1], depth: maxDepth)
        }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        
        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }

    private func subdivideLargePolygon(_ points: [SCNVector3]) -> [SCNVector3] {
        var result: [SCNVector3] = []
        let radius: Float = 5.02
        
        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]
            
            result.append(p1)
            
            // İki nokta arasındaki büyük daire mesafesini hesapla
            let dot = (p1.x * p2.x + p1.y * p2.y + p1.z * p2.z) / (radius * radius)
            let angle = acos(min(1, max(-1, dot)))
            
            if angle > 0.05 { // Daha küçük açı eşiği
                let subdivisions = Int(angle * 40) // Daha fazla alt bölüm
                
                for j in 1..<subdivisions {
                    let t = Float(j) / Float(subdivisions)
                    let sphericalT = sin((1 - t) * angle) / sin(angle)
                    let sphericalT2 = sin(t * angle) / sin(angle)
                    
                    let x = sphericalT * p1.x + sphericalT2 * p2.x
                    let y = sphericalT * p1.y + sphericalT2 * p2.y
                    let z = sphericalT * p1.z + sphericalT2 * p2.z
                    
                    let length = sqrt(x * x + y * y + z * z)
                    let point = SCNVector3(
                        x / length * radius,
                        y / length * radius,
                        z / length * radius
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

    private func projectToSphere(latitude: Double, longitude: Double) -> SCNVector3 {
        let radius: Float = 5.02 // Update from 5.0 to ensure consistent sphere radius
        let phi = Float((90 - latitude) * .pi / 180)
        let theta = Float((longitude + 180) * .pi / 180)

        let x = -radius * sin(phi) * cos(theta)
        let y = radius * cos(phi)
        let z = radius * sin(phi) * sin(theta)

        return SCNVector3(x, y, z)
    }

    private func createBorderGeometry(from points: [SCNVector3]) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        let borderWidth: Float = 0.02 // Adjust border thickness
        
        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]
            
            // Calculate perpendicular vector for border width
            let direction = SCNVector3(
                p2.x - p1.x,
                p2.y - p1.y,
                p2.z - p1.z
            )
            let up = normalizeVector(p1) // Use surface normal as up vector
            let right = crossProduct(direction, up)
            let normalizedRight = normalizeVector(right)
            
            // Create four vertices for each border segment
            let v1 = SCNVector3(
                p1.x + normalizedRight.x * borderWidth,
                p1.y + normalizedRight.y * borderWidth,
                p1.z + normalizedRight.z * borderWidth
            )
            let v2 = SCNVector3(
                p1.x - normalizedRight.x * borderWidth,
                p1.y - normalizedRight.y * borderWidth,
                p1.z - normalizedRight.z * borderWidth
            )
            let v3 = SCNVector3(
                p2.x + normalizedRight.x * borderWidth,
                p2.y + normalizedRight.y * borderWidth,
                p2.z + normalizedRight.z * borderWidth
            )
            let v4 = SCNVector3(
                p2.x - normalizedRight.x * borderWidth,
                p2.y - normalizedRight.y * borderWidth,
                p2.z - normalizedRight.z * borderWidth
            )
            
            // Project vertices to sphere surface
            let radius: Float = 5.02
            func projectToSphere(_ v: SCNVector3) -> SCNVector3 {
                let length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
                return SCNVector3(
                    v.x / length * radius,
                    v.y / length * radius,
                    v.z / length * radius
                )
            }
            
            let pv1 = projectToSphere(v1)
            let pv2 = projectToSphere(v2)
            let pv3 = projectToSphere(v3)
            let pv4 = projectToSphere(v4)
            
            let baseIndex = Int32(vertices.count)
            vertices.append(pv1)
            vertices.append(pv2)
            vertices.append(pv3)
            vertices.append(pv4)
            
            // Create two triangles for the border segment
            indices.append(baseIndex)
            indices.append(baseIndex + 1)
            indices.append(baseIndex + 2)
            
            indices.append(baseIndex + 1)
            indices.append(baseIndex + 3)
            indices.append(baseIndex + 2)
        }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        
        return SCNGeometry(sources: [vertexSource], elements: [element])
    }

    private func crossProduct(_ v1: SCNVector3, _ v2: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            v1.y * v2.z - v1.z * v2.y,
            v1.z * v2.x - v1.x * v2.z,
            v1.x * v2.y - v1.y * v2.x
        )
    }

    private func updateHighlightedCountry(in sceneView: SCNView) {
        sceneView.scene?.rootNode.enumerateChildNodes { (node, _) in
            if let countryName = node.name {
                if countryName == highlightedCountry {
                    // Highlight the border
                    node.geometry?.firstMaterial?.diffuse.contents = UIColor.yellow
                    node.geometry?.firstMaterial?.transparency = 1
                } else {
                    // Reset to default border style
                    node.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.3)
                    node.geometry?.firstMaterial?.transparency = 0
                }
            }
        }
    }
    
    private func normalize(_ vector: SCNVector3) -> SCNVector3 {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
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

