{parseRle} = require "../rle"

container = undefined
stats = undefined
camera = undefined
scene = undefined
renderer = undefined
controls = undefined
stepsPerMs = 10 / 1000

showStats = false

palette = [0xfe8f0f, 0xf7325e, 0x7dc410, 0xfef8cf, 0x0264ed]

class WorkerFlyingCurves
  constructor: ->
    @worker = new Worker "./tubing_worker_browser.js"
    @worker.addEventListener "message", (e)=>@_onMsg(e)

    
    @scale = scale = 30
    @group = new THREE.Object3D
    @chunks = []
    @zMin = -4000 / scale
    @zMax = 4000 / scale
    @lastChunkZ = 0

    @group.scale.set scale, scale, scale
    @ready = false
    @taskId2dummyChunks = {}
    @nextTaskId = 0
    #continue initialization after the worker is ready
    pattern = parseRle "$3b2o$2bobob2o$2bo5bo$7b2o$b2o$bo5bo$2b2obobo$5b2obo"
    #pattern = parseRle "26bo$24bobo$25bo3$25bo$20bo3bobo$18bobo5bo$19bo3$19bo$14bo3bobo$12bobo5bo$13bo3$13bo$8bo3bobo$6bobo5bo$7bo3$7bo$2bo3bobo$obo5bo$bo"
    #pattern = parseRle "b2o2$b2o2$b2o2$b2o2$b2o2$b2o2$3bo$2bo"
    @loadPattern pattern
    
  _finishInitialize: (nCells, fldWidth, fldHeight, chunkLen)->
    @colors = (palette[i%palette.length] for i in [0...nCells] by 1)
    @materials = for color in @colors
      new THREE.MeshBasicMaterial color: color

    @group.position.set -0.5*fldWidth*@scale, -0.5*fldHeight*@scale, 0
    @group.updateMatrix()
    @ready = true
    @chunkLen = chunkLen
    console.log "Initializatoin finished"
    
  _onMsg: (e)->
    cmd = e.data.cmd
    unless cmd?
      console.log "Bad message received! #{JSON.stringify e.data}"
      return
    switch cmd
      when "init"
        @_finishInitialize e.data.nCells, e.data.fldWidth, e.data.fldHeight, e.data.chunkLen
      when "chunk"
        @_receiveChunk e.data.blueprint, e.data.taskId
      else
        console.log "Unknown responce #{e.cmd}"

  #returns: tuple [chunk, taskId]
  # chunk is an empty object
  # taskId is ID of the sent task
  requestChunk: ->
    taskId = @nextTaskId
    @nextTaskId = (taskId + 1) % 65536 #just because.
    @worker.postMessage
      cmd: "chunk"
      taskId: taskId
    dummy = new THREE.Object3D
    @taskId2dummyChunks[taskId] = dummy
    return [dummy, taskId]
    
  _receiveChunk: (blueprint, taskId)->
    chunk = @taskId2dummyChunks[taskId]
    #discard unexpected chunks
    return unless chunk?    
    delete @taskId2dummyChunks[taskId]
    i = 0

    #We must process all tubes in 75% of the chunk flyby time
    minTimePerTube = 10 #100 tubes/second
    chunkFlybyTime = @chunkLen / stepsPerMs

    #How many pieces to split blueprint to
    completionTime = Math.min(1000, chunkFlybyTime * 0.75)
    nPieces = completionTime/minTimePerTube | 0
    nPieces = Math.min(nPieces, blueprint.length)

    tubesPerPart = Math.ceil(blueprint.length / nPieces) | 0
    processingDelay = completionTime / nPieces
    
    processPart = =>
      for j in [0...Math.min(blueprint.length-1-i, tubesPerPart)] by 1
        tubeBp = blueprint[i]
        tubeGeom = @createTube tubeBp
        tube = new THREE.Mesh tubeGeom, @materials[i]
        chunk.add tube
        i+=1
      if i < blueprint.length-1
        setTimeout processPart, processingDelay
        
    processPart()
    #console.log "Received chunk!"
    return
    
  createTube: (blueprint)->
    tube = new THREE.BufferGeometry()
    
    tube.addAttribute 'position', new THREE.BufferAttribute(blueprint.v, 3)
    tube.addAttribute 'index', new THREE.BufferAttribute(blueprint.idx, 1)
    #tube.computeBoundingSphere() #do we need it?
    return  tube

  #remove all tubes, return to the initial state.
  reset: ->
    #we don't expect any more chunks
    @taskId2dummyChunks = {}
    @lastChunkZ = 0
    for chunk in @chunks
      @group.remove chunk
    return
    
  loadPattern: (pattern) ->
    @reset()
    @worker.postMessage
      cmd: "init"
      pattern: pattern
      chunkSize: 500
      skipSteps: 1
      size: 128
      # _finishInitialize invoked on responce
    
  step: (dz) ->
    unless @ready
      #console.log "Worker not ready yet..."
      return
      
    i = 0
    while i < @chunks.length
      chunk = @chunks[i]
      chunk.position.setZ chunk.position.z-dz
      if chunk.position.z < @zMin
        #console.log "Discarding chunk #{i}"
        @chunks.splice i, 1
        @group.remove chunk
      else
        i += 1
        
    @lastChunkZ -= dz
    if @lastChunkZ < @zMax
      #console.log "last chunk is at #{@lastChunkZ}, Requesting new chunk..."
      #Posts request to the worker and quickly returns dummy
      [chunk, taskId] = @requestChunk()
      @lastChunkZ += @chunkLen
      chunk.position.setZ @lastChunkZ
      @chunks.push chunk
      @group.add chunk
      #console.log "Requested #{taskId}, added dummy at #{@lastChunkZ} chunk of len #{@chunkLen}"
    return
        

curves = undefined    
          
init = ->
  container = document.getElementById("container")
  
  #
  camera = new THREE.PerspectiveCamera(27, window.innerWidth / window.innerHeight, 1, 10500)
  camera.position.set 500, 0, -1750
  scene = new THREE.Scene()
  scene.fog = new THREE.Fog 0x050505, 2000, 10500
  #scene.add new THREE.AmbientLight 0x444444 

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

  #curves = new ChunkedFlyingCurves
  curves = new WorkerFlyingCurves
  
  lines = new THREE.Object3D
  lines.add curves.group
  scene.add lines
  
  #
  renderer = new THREE.WebGLRenderer(antialias: false)
  renderer.setSize window.innerWidth, window.innerHeight
  renderer.gammaInput = true
  renderer.gammaOutput = true
  container.appendChild renderer.domElement
  
  #
  if showStats
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
  
showPatternsWindow = ->
  patterns = document.getElementById "patterns-window"
  
  patterns.style.display = ""

hidePatternsWindow = ->
  patterns = document.getElementById "patterns-window"
  
  patterns.style.display = "none"
  
  
bindEvents = ->
  E = (eid)->document.getElementById eid
  setSpeed = (speed) -> (e) -> stepsPerMs = speed * 1e-3
  E("btn-speed-0").addEventListener "click", setSpeed 0
  E("btn-speed-1").addEventListener "click", setSpeed 10
  E("btn-speed-2").addEventListener "click", setSpeed 30
  E("btn-speed-3").addEventListener "click", setSpeed 100
  E("btn-speed-4").addEventListener "click", setSpeed 300

  E("btn-show-patterns").addEventListener "click", showPatternsWindow

prevTime = null

animate = ->
  requestAnimationFrame animate
  render()
  controls.update()
  stats?.update()

  time = Date.now()
  if prevTime isnt null
    dt = Math.min(time-prevTime, 100) #if FPS fals below 10, slow down simulation instead.
    curves.step stepsPerMs * dt
  prevTime = time
  return
  
render = ->
  renderer.render scene, camera
  return
  
Detector.addGetWebGLMessage()  unless Detector.webgl
bindEvents()
init()
animate()