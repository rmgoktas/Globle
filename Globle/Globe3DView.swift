import SwiftUI
import SceneKit

struct Globe3DView: UIViewRepresentable {
    var geoJson: GeoJson
    var highlightedCountry: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

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

        context.coordinator.sceneView = sceneView
        context.coordinator.globeNode = globeNode
        context.coordinator.cameraNode = cameraNode

        addCountries(to: globeNode)

        // Küreyi yavaşça döndürme animasyonu ekleme
        let rotateAction = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 60)
        let repeatAction = SCNAction.repeatForever(rotateAction)
        globeNode.runAction(repeatAction)

        // İlk odaklanma işlemi için asenkron çağrı
        DispatchQueue.main.async {
            context.coordinator.focusOnCountry(self.highlightedCountry)
        }

        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // Vurgu yapılan ülkeyi güncelle
        context.coordinator.updateHighlightedCountry(highlightedCountry)
    }
    
    private func createGlobe() -> SCNNode {
        let sphere = SCNSphere(radius: 5)
        let material = SCNMaterial()
        material.diffuse.contents = UIImage(named: "earth")
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeTranslation(-0.249, 0, 0) // Dokusu ayarlama
        material.specular.contents = UIColor.white
        material.shininess = 0.1
        material.lightingModel = .blinn
        sphere.materials = [material]

        let globeNode = SCNNode(geometry: sphere)
        globeNode.name = "globe"
        return globeNode
    }

    class Coordinator: NSObject {
        var parent: Globe3DView
        weak var sceneView: SCNView?
        weak var globeNode: SCNNode?
        weak var cameraNode: SCNNode?

        init(_ parent: Globe3DView) {
            self.parent = parent
        }

        func focusOnCountry(_ countryName: String) {
            guard let feature = parent.geoJson.features.first(where: { $0.countryName?.mytrimmed().capitalized == countryName.mytrimmed().capitalized }),
                  let center = parent.calculateCountryCenter(for: feature),
                  let sceneView = sceneView,
                  let globeNode = globeNode,
                  let cameraNode = cameraNode else {
                return
            }

            // Küreyi döndürmeyi durdur
            globeNode.removeAllActions()

            // Kamera pozisyonunu ayarlama
            let distance: Float = 20.0

            // Kameranın kürenin merkezine bakmasını sağla
            let direction = normalizeVector(SCNVector3(-center.x, -center.y, -center.z))
            let newCameraPosition = SCNVector3(
                direction.x * distance,
                direction.y * distance,
                direction.z * distance
            )

            let moveAction = SCNAction.move(to: newCameraPosition, duration: 1.0)
            cameraNode.runAction(moveAction)

            // Kameranın her zaman kürenin merkezine bakmasını sağla
            let lookAtConstraint = SCNLookAtConstraint(target: globeNode)
            lookAtConstraint.isGimbalLockEnabled = true
            cameraNode.constraints = [lookAtConstraint]

            // Küreyi döndürme
            let rotationAction = SCNAction.rotateTo(
                x: 0,
                y: CGFloat(-atan2(direction.x, direction.z)),
                z: 0,
                duration: 1.0,
                usesShortestUnitArc: true
            )
            globeNode.runAction(rotationAction)

            // SceneView ile ek etkileşimler (örneğin ışık ekleme)
            if let light = sceneView.scene?.rootNode.light {
                light.color = UIColor.white
            }
        }
        func updateHighlightedCountry(_ countryName: String) {
            guard let sceneView = sceneView else { return }
            sceneView.scene?.rootNode.enumerateChildNodes { (node, _) in
                if let name = node.name {
                    if name == countryName {
                        // Vurgu yapılan ülkenin merkezine odaklan
                        focusOnCountry(countryName)

                        // Ülkenin sınırlarını vurgula
                        node.geometry?.firstMaterial?.diffuse.contents = UIColor.yellow
                        node.geometry?.firstMaterial?.transparency = 1
                    } else {
                        // Diğer ülkeleri varsayılan stil ile ayarla
                        node.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.3)
                        node.geometry?.firstMaterial?.transparency = 0.7
                    }
                }
            }
        }

        private func normalizeVector(_ v: SCNVector3) -> SCNVector3 {
            let length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
            return SCNVector3(v.x / length, v.y / length, v.z / length)
        }
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

            if let center = calculateCountryCenter(for: feature) {
                let dotGeometry = SCNSphere(radius: 0.05)
                let dotMaterial = SCNMaterial()
                dotMaterial.diffuse.contents = UIColor.white
                dotGeometry.materials = [dotMaterial]

                let dotNode = SCNNode(geometry: dotGeometry)
                dotNode.position = center
                dotNode.name = "\(String(describing: feature.countryName))_dot"
                countriesNode.addChildNode(dotNode)
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

            // Sınır geometrisi oluşturma
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
        let radius: Float = 5.02 // Yarıçapı tutarlı hale getirme
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
        let borderWidth: Float = 0.02 // Sınır kalınlığını ayarlama

        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]

            // Sınır kalınlığı için dik vektör hesaplama
            let direction = SCNVector3(
                p2.x - p1.x,
                p2.y - p1.y,
                p2.z - p1.z
            )
            let up = normalizeVector(p1) // Yüzey normalini kullan
            let right = crossProduct(direction, up)
            let normalizedRight = normalizeVector(right)

            // Her sınır segmenti için dört vertex oluşturma
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

            // Vertex'ları küre yüzeyine projekte etme
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

            // Sınır segmenti için iki üçgen oluşturma
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
