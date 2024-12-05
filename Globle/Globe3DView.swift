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
        sphere.firstMaterial?.diffuse.contents = UIColor.blue.withAlphaComponent(0.3)
        
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
            
            let geometry = SCNGeometry.polygonGeometry(points: points)
            let countryNode = SCNNode(geometry: geometry)
            countryNode.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.7)
            countryNode.geometry?.firstMaterial?.isDoubleSided = true
            countryNode.name = feature.countryName
            node.addChildNode(countryNode)
        }
    }
    
    private func projectToSphere(latitude: Double, longitude: Double) -> SCNVector3? {
        let radius: Float = 5.0
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
            if node.name == highlightedCountry {
                node.geometry?.firstMaterial?.diffuse.contents = UIColor.red.withAlphaComponent(0.7)
            } else {
                node.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.7)
            }
        }
    }
}

extension SCNGeometry {
    static func polygonGeometry(points: [SCNVector3]) -> SCNGeometry {
        let source = SCNGeometrySource(vertices: points)
        
        var indices = [Int32]()
        for i in 1..<(points.count - 1) {
            indices.append(0)
            indices.append(Int32(i))
            indices.append(Int32(i + 1))
        }
        
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [source], elements: [element])
    }
}

