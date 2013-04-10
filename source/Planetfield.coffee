root = exports ? this

root.planetBufferSize = 100

class root.Planetfield
	constructor: ({starfield, maxPlanetsPerSystem, minOrbitScale, maxOrbitScale, planetSize, nearRange, farRange}) ->
		@_starfield = starfield
		@_planetBufferSize = root.planetBufferSize

		@nearRange = nearRange
		@farRange = farRange
		@planetSize = planetSize

		@maxPlanetsPerSystem = maxPlanetsPerSystem
		@minOrbitScale = minOrbitScale
		@maxOrbitScale = maxOrbitScale

		randomStream = new RandomStream(universeSeed)

		# load planet shader
		@shader = xgl.loadProgram("planetfield")
		@shader.uniforms = xgl.getProgramUniforms(@shader, ["modelViewMat", "projMat", "spriteSizeAndViewRangeAndBlur"])
		@shader.attribs = xgl.getProgramAttribs(@shader, ["aPos", "aUV"])

		# we just re-use the index buffer from the starfield because the sprites are indexed the same
		@iBuff = @_starfield.iBuff
		if @_planetBufferSize*6 > @iBuff.numItems
			console.log("Warning: planetBufferSize should not be larger than starBufferSize. Setting planetBufferSize = starBufferSize.")
			@_planetBufferSize = @iBuff.numItems

		# prepare vertex buffer
		@buff = new Float32Array(@_planetBufferSize * 4 * 6)
		j = 0
		for i in [0 .. @_planetBufferSize-1]
			randAngle = randomStream.range(0, Math.PI*2)

			for vi in [0..3]
				angle = ((vi - 0.5) / 2.0) * Math.PI + randAngle
				u = Math.sin(angle) * Math.sqrt(2) * 0.5
				v = Math.cos(angle) * Math.sqrt(2) * 0.5
				marker = if vi <= 1 then 1 else -1

				@buff[j+3] = u
				@buff[j+4] = v
				@buff[j+5] = marker
				j += 6

		@vBuff = gl.createBuffer()
		@vBuff.itemSize = 6
		@vBuff.numItems = @_planetBufferSize * 4

		# prepare to render higher resolution planets as well
		#@lowresGeom = new PlanetLowresGeometry(32)


	setPlanetSprite: (index, position) ->
		j = index * 6*4
		for vi in [0..3]
			@buff[j] = position[0]
			@buff[j+1] = position[1]
			@buff[j+2] = position[2]
			j += 6


	updatePlanetSprites: (position, originOffset) ->
		starList = @_starfield.queryStars(position, originOffset, @farRange)

		#if starList.length * @maxPlanetsPerSystem > @_planetBufferSize
		# sort star list from nearest to farthest
		starList.sort( ([ax,ay,az,aw], [cx,cy,cz,cw]) -> (ax*ax + ay*ay + az*az) - (cx*cx + cy*cy + cz*cz) )

		randomStream = new RandomStream()
		@numPlanets = 0

		for [dx, dy, dz, w] in starList
			randomStream.seed = w * 1000000

			systemPlanets = randomStream.intRange(0, @maxPlanetsPerSystem)
			if @numPlanets + systemPlanets > @_planetBufferSize then break

			for i in [1 .. systemPlanets]
				radius = @_starfield.starSize * randomStream.range(@minOrbitScale, @maxOrbitScale)
				angle = randomStream.radianAngle()
				[orbitX, orbitY, orbitZ] = [radius * Math.sin(angle), radius * Math.cos(angle), w * Math.sin(angle)]

				@setPlanetSprite(@numPlanets, [dx+orbitX, dy+orbitY, dz+orbitZ])
				@numPlanets++


	render: (camera, originOffset, blur) ->
		# populate vertex buffer with planet positions
		@updatePlanetSprites(camera.position, originOffset)

		# return if nothing to render
		if @numPlanets <= 0 then return

		# push render state
		@_startRender()

		# upload planet sprite vertices
		gl.bufferData(gl.ARRAY_BUFFER, @buff, gl.DYNAMIC_DRAW)

		# basic setup
		@vBuff.usedItems = Math.floor(@vBuff.usedItems)
		if @vBuff.usedItems <= 0 then return
		seed = Math.floor(Math.abs(seed))

		# planet sprite positions in the vertex buffer are relative to camera position, so the model matrix adds back
		# the camera position. the view matrix will then be composed which then reverses this, producing the expected resulting
		# view-space positions in the vertex shader. this may seem a little roundabout but the alternate would be to implement 
		# a "camera.viewMatrixButRotationOnlyBecauseIWantToDoViewTranslationInMyDynamicVertexBufferInstead".
		modelViewMat = mat4.create()
		mat4.translate(modelViewMat, modelViewMat, camera.position)
		mat4.mul(modelViewMat, camera.viewMat, modelViewMat)

		# set shader uniforms
		gl.uniformMatrix4fv(@shader.uniforms.projMat, false, camera.projMat)
		gl.uniformMatrix4fv(@shader.uniforms.modelViewMat, false, modelViewMat)
		gl.uniform4f(@shader.uniforms.spriteSizeAndViewRangeAndBlur, @planetSize, @nearRange, @farRange, blur)

		# issue draw operation
		gl.drawElements(gl.TRIANGLES, @numPlanets*6, gl.UNSIGNED_SHORT, 0)

		# pop render state
		@_finishRender()


	_startRender: ->
		gl.disable(gl.DEPTH_TEST)
		gl.disable(gl.CULL_FACE)
		gl.depthMask(false)
		gl.enable(gl.BLEND)
		gl.blendFunc(gl.ONE, gl.ONE)

		gl.useProgram(@shader)

		gl.bindBuffer(gl.ARRAY_BUFFER, @vBuff)
		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, @iBuff)

		gl.enableVertexAttribArray(@shader.attribs.aPos)
		gl.vertexAttribPointer(@shader.attribs.aPos, 3, gl.FLOAT, false, @vBuff.itemSize*4, 0)
		gl.enableVertexAttribArray(@shader.attribs.aUV)
		gl.vertexAttribPointer(@shader.attribs.aUV, 3, gl.FLOAT, false, @vBuff.itemSize*4, 4 *3)


	_finishRender: ->
		gl.disableVertexAttribArray(@shader.attribs.aPos)
		gl.disableVertexAttribArray(@shader.attribs.aUV)

		gl.bindBuffer(gl.ARRAY_BUFFER, null)
		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, null)

		gl.useProgram(null)

		gl.disable(gl.BLEND)
		gl.depthMask(true)
		gl.enable(gl.DEPTH_TEST)
		gl.enable(gl.CULL_FACE)

