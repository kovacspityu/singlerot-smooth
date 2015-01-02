{Simulator, CircularInterpolatingSimulator} = require "../revca_track"
{parseRle} = require "../rle"

container = undefined
stats = undefined
camera = undefined
scene = undefined
renderer = undefined
mesh = undefined
controls = undefined

palette = [0xfe8f0f, 0xf7325e, 0x7dc410, 0xfef8cf, 0x0264ed]

class FlowingLine
  constructor: (@segments, color) ->
    @geometry = new THREE.BufferGeometry()
    @geometry.dynamic = true
    @material = new THREE.LineBasicMaterial({vertexColors: THREE.VertexColors, linewidth:3})
    @positions = new Float32Array(segments * 3)
    @colors = new Float32Array(segments * 3)
    
    @geometry.addAttribute "position", new THREE.BufferAttribute(@positions, 3)
    @geometry.addAttribute "color", new THREE.BufferAttribute(@colors, 3)
    #@geometry.computeBoundingSphere()
    @mesh = new THREE.Line(@geometry, @material)

    r = color & 0xff
    g = (color >> 8) & 0xff
    b = (color >> 16) & 0xff
    @color = [r/255.0,g/255.0,b/255.0]
    
  setDirty: ->
    @geometry.attributes[ "position" ].needsUpdate = true
    @geometry.attributes[ "color" ].needsUpdate = true
    @geometry.needsUpdate = true
    
  initial: (x, y, z0, z1) ->
    ps = @positions
    cs = @colors
    [r,g,b] = @color
    for i in [0...@segments] by 1
      i3=i*3
      z = z0 + ((z1-z0)/(@segments-1))*i
      ps[i3] = x
      ps[i3+1] = y
      ps[i3+2] = z
      cs[i3]=r
      cs[i3+1]=g
      cs[i3+2]=b
    @setDirty()
      
  flow: (x, y) ->
    ps = @positions
    for i in [0...(@segments-1)] by 1
      i3=i*3
      ps[i3] = ps[i3+3]
      ps[i3+1] = ps[i3+4]
    i3 = (@segments-1)*3
    delta = Math.abs(ps[i3]-x) + Math.abs(ps[i3+1]-y)
    if delta > 100
      ps[i3-3]=NaN
      ps[i3-2]=NaN
    ps[i3]   =x
    ps[i3+1] =y
    @setDirty()

class FlyingCurves
  constructor: ->

    pattern = parseRle "$3b2o$2bobob2o$2bo5bo$7b2o$b2o$bo5bo$2b2obobo$5b2oo"
    simulator = new Simulator 32, 32 #field size
    simulator.put pattern, 12, 12 #pattern roughly at the center
    
    order = 3
    interpSteps = 3
    smoothing = 12
    @isim = new CircularInterpolatingSimulator simulator, order, interpSteps, smoothing

    #Create geometry
    @segments = 500
    @scale = 30
    state = @isim.getInterpolatedState()
    z0 = -1400
    z1 = 400
    @group = new THREE.Object3D
    @lines = for i in [0...state.length] by 2
      line = new FlowingLine @segments, palette[ (i/2) % palette.length ]
      line.initial (state[i]-16)*@scale, (state[i+1]-16)*@scale, z0, z1
      @group.add line.mesh
      line
    console.log "Created #{@lines.length} lines"
  step: ->
    @isim.nextTime 1
    state = @isim.getInterpolatedState()
    for line, i in @lines
      i2 = i*2
      line.flow (state[i2]-16)*@scale, (state[i2+1]-16)*@scale
      #if i is 0
      #  console.log "Point 0: #{state[i2]}, #{state[i2+1]}"
    return
      
curves = undefined    
          
init = ->
  container = document.getElementById("container")
  
  #
  camera = new THREE.PerspectiveCamera(27, window.innerWidth / window.innerHeight, 1, 4000)
  camera.position.z = 2750
  scene = new THREE.Scene()

  controls = new THREE.TrackballControls  camera

  controls.rotateSpeed = 1.0
  controls.zoomSpeed = 1.2
  controls.panSpeed = 0.8

  controls.noZoom = false
  controls.noPan = false

  controls.staticMoving = true
  controls.dynamicDampingFactor = 0.3

  controls.keys = [ 65, 83, 68 ]

  #controls.addEventListener 'change', render

  curves = new FlyingCurves
    
  mesh = curves.group
  scene.add mesh
  
  #
  renderer = new THREE.WebGLRenderer(antialias: false)
  renderer.setSize window.innerWidth, window.innerHeight
  renderer.gammaInput = true
  renderer.gammaOutput = true
  container.appendChild renderer.domElement
  
  #
  stats = new Stats()
  stats.domElement.style.position = "absolute"
  stats.domElement.style.top = "0px"
  container.appendChild stats.domElement
  
  #
  window.addEventListener "resize", onWindowResize, false
  return
  
onWindowResize = ->
  camera.aspect = window.innerWidth / window.innerHeight
  camera.updateProjectionMatrix()
  renderer.setSize window.innerWidth, window.innerHeight
  controls.handleResize()
  return

animate = ->
  requestAnimationFrame animate
  render()
  controls.update()
  stats.update()
  for i in [1..5]
    curves.step()
  return
  
render = ->
  #time = Date.now() * 0.0001
  #mesh.rotation.x = time * 0.25
  #mesh.rotation.y = time * 0.5
  renderer.render scene, camera
  return
  
Detector.addGetWebGLMessage()  unless Detector.webgl
init()
animate()