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
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 20)
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
                addPolygons(polygons, to: countriesNode, for: feature)
            } else if let multiPolygons = feature.geometry.coordinates.multiPolygon {
                for polygons in multiPolygons {
                    addPolygons(polygons, to: countriesNode, for: feature)
                }
            }
        }

        globeNode.addChildNode(countriesNode)
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
                    node.geometry?.firstMaterial?.transparency = 0.7
                }
            }
        }
    }
    
    private func normalize(_ vector: SCNVector3) -> SCNVector3 {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
    }
    
    private func focusOnCountry(_ countryName: String, in sceneView: SCNView) {
        guard let feature = geoJson.features.first(where: { $0.countryName?.trimmed().capitalized == countryName.trimmed().capitalized }),
              let center = calculateCountryCenter(for: feature) else {
            return
        }

        let cameraNode = sceneView.pointOfView!
        let globeNode = sceneView.scene!.rootNode.childNodes.first!

        // Calculate the rotation needed to face the country
        let currentPosition = cameraNode.position
        let directionToCountry = SCNVector3(center.x - currentPosition.x, center.y - currentPosition.y, center.z - currentPosition.z)
        let rotationAction = SCNAction.rotateTo(x: CGFloat(-asin(directionToCountry.y / 15)),
                                                y: CGFloat(atan2(directionToCountry.x, directionToCountry.z)),
                                                z: 0,
                                                duration: 1,
                                                usesShortestUnitArc: true)

        // Rotate the globe instead of the camera
        globeNode.runAction(rotationAction)
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

extension String {
    func mytrimmed() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
