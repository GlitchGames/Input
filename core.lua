--[[
MIT License

Copyright (c) 2023 Graham Ranson of Glitch Games Ltd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

--- Class creation.
local Input = {}

-- Required libraries.
local json = require( "json" )

-- Localised functions.
local decode = json.decode
local encode = json.encode
local DocumentsDirectory = system.DocumentsDirectory
local ResourceDirectory = system.ResourceDirectory
local open = io.open
local close = io.close
local atan2 = math.atan2
local abs = math.abs
local sqrt = math.sqrt

-- Localised values.
local pi = math.pi

-- Static values.
Input.ButtonState = {}
Input.ButtonState.Released = "released"
Input.ButtonState.Pressed = "pressed"
Input.ButtonState.JustReleased = "justReleased"
Input.ButtonState.JustPressed = "justPressed"

Input.ButtonPhase = {}
Input.ButtonPhase.Down = "down"
Input.ButtonPhase.Up = "up"

Input.MouseButton = {}
Input.MouseButton.Primary = "primary"
Input.MouseButton.Secondary = "secondary"
Input.MouseButton.Middle = "middle"

Input.MouseScroll = {}
Input.MouseScroll.Left = "scrollLeft"
Input.MouseScroll.Right = "scrollRight"
Input.MouseScroll.Up = "scrollUp"
Input.MouseScroll.Down = "scrollDown"

Input.MouseScrollDirection = {}
Input.MouseScrollDirection.Left = -1
Input.MouseScrollDirection.Right = 1
Input.MouseScrollDirection.Up = 1
Input.MouseScrollDirection.Down = -1

Input.ThumbStick = {}
Input.ThumbStick.Left = "left"
Input.ThumbStick.Right = "right"

function Input:new( params )
	
	-- Tables to store button phases and states
	self._buttonPhases = {}
	self._buttonStates = {}
	
	-- Table to store stick values
	self._sticks = {}
	
	-- Table to store named actions
	self._actions = params.actions or {}
	self._actionBindings = {}
	
	local platform = system.getInfo( "platform" )
	
	if platform == "nx64" then
		Runtime:addEventListener( "touch", self )
		Runtime:addEventListener( "key", self )
		Runtime:addEventListener( "axis", self )
	elseif platform == "win32" or platform == "macos" or platform == "html5" then
		Runtime:addEventListener( "mouse", self )
		Runtime:addEventListener( "key", self )
		Runtime:addEventListener( "axis", self )
	elseif platform == "android" or platform == "ios" then
		Runtime:addEventListener( "touch", self )
	elseif platform == "tvos" then
		if system.getInfo( "environment" ) == "simulator" then
			Runtime:addEventListener( "mouse", self )
		end
		Runtime:addEventListener( "key", self )
	end
	
	self.onDeviceConnected = 
	{
		params.onDeviceConnected
	}
	
	self.onDeviceDisconnected = 
	{
		params.onDeviceDisconnected
	}
	
	Runtime:addEventListener( "inputDeviceStatus", self )
	
	return self
	
end

--- Call this function after you've created the Input library.
function Input:postInit()
	
	self:refreshInputDevices()
	
	for i = 1, #self._devices, 1 do
		for j = 1, #self.onDeviceConnected, 1 do
			if self.onDeviceConnected[ j ] and type( self.onDeviceConnected[ j ] ) == "function" then
				self.onDeviceConnected[ j ]{ device = self._devices[ i ], playerNumber = self:getPlayerNumberFromDevice( self._devices[ i ] ) }
			end
		end	
	end
	
end

--- Refreshes the list of all connected devices.
function Input:refreshInputDevices()
	self._devices = system.getInputDevices()
end

--- Gets a list of all connected devices.
-- @return The connected devices.
function Input:getConnectedDevices()
	return self._devices	
end

--- Gets the player number associated with a device.
-- @param device The device.
-- @return The player number.
function Input:getPlayerNumberFromDevice( device )
	if device.playerNumber then
		return device.playerNumber
	else
		if device.descriptor then
			local playerNumber = string.gsub( device.descriptor, "Gamepad ", "" )
			return tonumber( playerNumber )
		else
			return 1
		end
	end
end


--- Gets the device associated with a player number.
-- @param playerNumber The player number.
-- @return The device.
function Input:getDeviceForPlayerNumber( playerNumber )
	for i = 1, #( self._devices or {} ), 1 do
		if self._devices[ i ].playerNumber == playerNumber or self._devices[ i ].playerNumber == nil and self._devices[ i ].descriptor == "Gamepad " .. playerNumber then
			return self._devices[ i ]
		end
	end
end

--- Register an action.
-- @param name The name of the action.
function Input:registerAction( name )
	self._actions[ #self._actions + 1 ] = name
end

--- Gets all registered actions.
-- @return The actions.
function Input:getRegisteredActions()
	return self._actions
end

--- Gets all actions associated for a certain button.
-- @param buttonName The name of the button.
-- @param device The device to check for.
-- @return The actions.
function Input:getActionsForButton( buttonName, device )
	
	self._actionBindings[ device or "keyboard" ] = self._actionBindings[ device or "keyboard" ] or {}
	
	return self._actionBindings[ device or "keyboard" ][ buttonName ]
	
end

--- Bind a button to an action.
-- @param buttonName The name of the button.
-- @param actionName the name of the action.
-- @param playerNumber The player number to bind them to.
function Input:bindButtonToAction( buttonName, actionName, playerNumber )
	
	local device = self:getDeviceForPlayerNumber( playerNumber ) or "keyboard"
	
	self._actionBindings[ device ] = self._actionBindings[ device ] or {}
	
	self._actionBindings[ device ][ buttonName ] = self._actionBindings[ device ][ buttonName ] or {}
	self._actionBindings[ device ][ buttonName ][ #self._actionBindings[ device ][ buttonName ] + 1 ] = actionName
	
end

--- Bind some controls to a device.
-- @param configPath The path to the binding file.
-- @param playerNumber The player number to bind them to.
-- @param baseDir The directory to load the config from. Defaults to ResourceDirectory.
-- @param append Should the bindings be appended to the current ones? Optional, defaults to false.
function Input:bindControls( configPath, playerNumber, baseDir, append )
	
	local device = self:getDeviceForPlayerNumber( playerNumber ) or "keyboard"
	
	self._actionBindings[ device ] = {}
	
	local bindings = self:loadBindings( configPath, baseDir )
	
	for k, v in pairs( bindings ) do
		if type( v ) == "string" then
			self:bindButtonToAction( v, k, playerNumber )
		elseif type( v ) == "table" then
			for i = 1, #v, 1 do
				self:bindButtonToAction( v[ i ], k, playerNumber )
			end
		end
	end
	
end

--- Loads a set of bindings from a file.
-- @param name The name of the bindings.
-- @param baseDir The directory to load them from. Defaults to ResourceDirectory.
-- @return The bindings.
function Input:loadBindings( name, baseDir )
	
	-- Path for the file to read
	local path = system.pathForFile( name .. ".binding", baseDir or ResourceDirectory )
	 
	-- Open the file handle
	local file, errorString = open( path, "r" )
	 
	local bindings = {}
	
	if not file then
		-- Error occurred; output the cause
		print( "File error: " .. errorString )
	else
		-- Read data from file
		local contents = file:read( "*a" )
		
		bindings = decode( contents )
		
		close( file )
		
	end
	 
	file = nil
	
	return bindings
	
end

--- Saves out some bindings to a .binding file in the DocumentsDirectory.
-- @param bindings The bindings to save.
-- @param name The name of the bindings.
function Input:saveBindings( bindings, name )
	
	local data = encode( bindings )
	
	-- Path for the file to write
	local path = system.pathForFile( name .. ".binding", DocumentsDirectory )
	 
	-- Open the file handle
	local file, errorString = open( path, "w" )
	 
	if not file then
		-- Error occurred; output the cause
		print( "File error: " .. errorString )
	else
		
		-- Write data to file
		file:write( data )
		
		-- Close the file handle
		close( file )
		
	end
	 
	file = nil
	
end

--- Gets the current bindings for a device.
-- @param device The device to check.
-- @return The bindings.
function Input:getBindingsForDevice( device )
	return self._actionBindings[ device ]
end

--- Sets a button phase.
-- @param button The name of the button.
-- @param phase The name of the phase, for options see Input.ButtonPhase.
-- @param device The device that was used.
function Input:setButtonPhase( name, phase, device )
	if not self:isButtonInState( name, phase, playerNumber ) then
		self._buttonPhases[ device or "keyboard" ] = self._buttonPhases[ device or "keyboard" ] or {}
		self._buttonPhases[ device or "keyboard" ][ name ] = phase
	end
end

--- Gets a button phase.
-- @param name The name of the button.
-- @param device The device that was used.
-- @return The current phase.
function Input:getButtonPhase( name, device )
	self._buttonPhases[ device or "keyboard" ] = self._buttonPhases[ device or "keyboard" ] or {}
	return self._buttonPhases[ device or "keyboard" ][ name ] or Input.ButtonPhase.Up
end

--- Checks if a button is currently in a specific phase.
-- @param name The name of the button.
-- @param phase The name of the phase, for options see Input.ButtonPhase.
-- @param device The device that was used.
-- @return True if it is, false otherwise.
function Input:isButtonInPhase( name, phase, device )
	return self:getButtonPhase( name, device or "keyboard" ) == phase
end

--- Sets a button state.
-- @param button The name of the button.
-- @param state The name of the state, for options see Input.ButtonState.
-- @param device The device that was used.
function Input:setButtonState( name, state, device )

	if name and not self:isButtonInState( name, state, device ) then
		
		self._buttonStates[ device or "keyboard" ] = self._buttonStates[ device or "keyboard" ] or {}
		
		local actions = self:getActionsForButton( name, device ) or {}

		for i = 1, #actions, 1 do
			
			-- Store out the state
			self._buttonStates[ device or "keyboard" ][ actions[ i ] ] = state

			-- Fire off a 'button' event with the button name, or paired action, and new state
			Runtime:dispatchEvent{ name = "button", button = actions[ i ], raw = name, state = state, playerNumber = self:getPlayerNumberFromDevice( device ), device = device }
			
		end
		
		Runtime:dispatchEvent{ name = "button", button = name, raw = name, state = state, playerNumber = self:getPlayerNumberFromDevice( device ), device = device }

		-- Store out the state
		self._buttonStates[ device or "keyboard" ][ name ] = state

	end

end

--- Gets a button state.
-- @param name The name of the button.
-- @param device The device that was used.
-- @return The current state.
function Input:getButtonState( name, device )
	return self._buttonStates[ device or "keyboard" ] and self._buttonStates[ device or "keyboard" ][ name ] or Input.ButtonState.Released
end

--- Checks if a button is currently in a specific state.
-- @param name The name of the button. Optional, will check all buttons if nil.
-- @param state The name of the state, for options see Input.ButtonState.
-- @param device The device that was used.
-- @return True if it is, false otherwise. If no button was passed in and one is pressed it'll also return the button name.
function Input:isButtonInState( name, state, device )

	-- Was a name passed in?
	if name then
		
		-- Check if this button is in the state, if so then return true as we only need one
		if self:getButtonState( name, device or "keyboard" ) == state then
			return true
		end
		
		-- No buttons are in the state
		return false
		
	else
		return self:isAnyButtonInState( state, playerNumber )
	end
	
end

--- Checks if any button is currently in a specific state.
-- @param state The name of the state, for options see Input.ButtonState.
-- @param playerNumber The number of the player. Optional, defaults to 1.
-- @return True if it is, false otherwise.
function Input:isAnyButtonInState( state, device )

	local button
	
	self._buttonStates[ device or "keyboard" ] = self._buttonStates[ device or "keyboard" ] or {}
	
	for k, v in pairs( self._buttonStates[ device or "keyboard" ] ) do
		
		if self:isButtonInState( k, state, device or "keyboard" ) then
			button = k
			break
		end
	end
	
	return button ~= nil, button

end

--- Checks if a button is currently pressed.
-- @param name The name of the button. Optional, will check all buttons if nil.
-- @return True if it is, false otherwise.
function Input:isButtonPressed( name, playerNumber )
	return self:isButtonInState( name, Input.ButtonState.Pressed, self:getDeviceForPlayerNumber( playerNumber ) )
end

--- Checks if a button is currently released.
-- @param name The name of the button. Optional, will check all buttons if nil.
-- @return True if it is, false otherwise.
function Input:isButtonReleased( name, playerNumber )
	return self:isButtonInState( name, Input.ButtonState.Released, self:getDeviceForPlayerNumber( playerNumber ) )
end

--- Checks if a button was just pressed.
-- @param name The name of the button. Optional, will check all buttons if nil.
-- @return True if it was, false otherwise.
function Input:wasButtonJustPressed( name, playerNumber )
	return self:isButtonInState( name, Input.ButtonState.JustPressed, self:getDeviceForPlayerNumber( playerNumber ) )
end

--- Checks if a button was just released.
-- @param name The name of the button. Optional, will check all buttons if nil.
-- @return True if it was, false otherwise.
function Input:wasButtonJustReleased( name, playerNumber )
	return self:isButtonInState( name, Input.ButtonState.JustReleased, self:getDeviceForPlayerNumber( playerNumber ) )
end

--- Gets the normalised values of a thumbstick.
-- @param stick The name of the stick - Input.ThumbStick.Left or Input.ThumbStick.Right.
-- @param playerNumber The number of the player. Optional, defaults to 1.
-- @return Table containing the normalised X and Y values.
function Input:getStickValues( stick, playerNumber )
	local device = self:getDeviceForPlayerNumber( playerNumber )
	if device then
		self._sticks[ device ] = self._sticks[ device ] or {}
		return self._sticks[ device ][ stick ]
	end
end

--- Gets the angle of a thumbstick.
-- @param stick The name of the stick - Input.ThumbStick.Left or Input.ThumbStick.Right.
-- @param offset The rotation offset of the controller. Optional, defaults to 0.
-- @param playerNumber The number of the player. Optional, defaults to 1.
-- @return The angle.
function Input:getStickAngle( stick, offset, playerNumber )

	local values = self:getStickValues( stick, playerNumber )
	
	if values then

		if values.x ~= 0 or values.y ~= 0 then

			local angleInRadians = atan2( values.y, values.x )
			local angleInDegrees = ( 180 / pi ) * angleInRadians

			local compassRadians = pi / 2 - angleInRadians
			local compassDegrees = ( 180 / pi ) * compassRadians

			compassDegrees = compassDegrees - 180

			local compassAngle = ( ( compassDegrees % 360 ) + 360 ) % 360

			compassAngle = abs( compassAngle - 360 )

			return compassAngle + ( offset or 0 )

		end

	end

end

--- Gets the distance the stick is away from the centre.
-- @param stick The name of the stick - Input.ThumbStick.Left or Input.ThumbStick.Right.
-- @param playerNumber The number of the player. Optional, defaults to 1.
-- @return The distance.
function Input:getStickDistance( stick, playerNumber )

	local values = self:getStickValues( stick, playerNumber )

	if values then
		return sqrt( values.x * values.x + values.y * values.y )
	end

end

--- Axis event listener.
-- @param event The event table.
function Input:axis( event )
	
	local device = event.device
	
	self._sticks[ device ] = self._sticks[ device ] or {}
	for k, v in pairs( Input.ThumbStick ) do
		self._sticks[ device ][ v ] = self._sticks[ device ][ v ] or { x = 0, y = 0 }
	end
	
	if event.axis.number == 1 then
		self._sticks[ device ][ Input.ThumbStick.Left ].x = event.normalizedValue	
	elseif event.axis.number == 2 then
		self._sticks[ device ][ Input.ThumbStick.Left ].y = event.normalizedValue
	elseif event.axis.number == 3 then
		self._sticks[ device ][ Input.ThumbStick.Right ].x = event.normalizedValue
	elseif event.axis.number == 4 then
		self._sticks[ device ][ Input.ThumbStick.Right ].y = event.normalizedValue
	end
	
	Runtime:dispatchEvent{ name = "input", type = "thumbstick", values = self._sticks[ device ], device = device, playerNumber = self:getPlayerNumberFromDevice( device ) }

end

--- Key event listener.
-- @param event The event table.
function Input:key( event )
	
	-- Set this key's phase
	self:setButtonPhase( event.keyName, event.phase, event.device )
	
end

--- Mouse event listener.
-- @param event The event table.
function Input:mouse( event )
	
end

--- Input device status listener.
-- @param event The event table.
function Input:inputDeviceStatus( event )
	
	self:refreshInputDevices()
	
	if event.connectionStateChanged then
		if event.device.isConnected then
			for i = 1, #self.onDeviceConnected, 1 do
				if self.onDeviceConnected[ i ] and type( self.onDeviceConnected[ i ] ) == "function" then
					self.onDeviceConnected[ i ]{ device = event.device, playerNumber = self:getPlayerNumberFromDevice( event.device ) }
				end
			end
		else
			for i = 1, #self.onDeviceDisconnected, 1 do
				if self.onDeviceDisconnected[ i ] and type( self.onDeviceDisconnected[ i ] ) == "function" then
					self.onDeviceDisconnected[ i ]{ device = event.device, playerNumber = self:getPlayerNumberFromDevice( event.device ) }
				end
			end
		end
	end
	
end

--- Update event handler. You must call this!
function Input:update()
	
	for device, phases in pairs( self._buttonPhases ) do
		
		-- Loop through all button phases
		for button, phase in pairs( phases ) do

			-- Get the state of this button
			local state = self:getButtonState( button, device )
			
			-- Do we have a state?
			if state then
		
				-- Is the button currently down?
				if phase == Input.ButtonPhase.Down then

					-- Was it just released or just pressed?
					if state == Input.ButtonState.JustPressed or state == Input.ButtonState.JustReleased then

						-- Mark it as being pressed
						self:setButtonState( button, Input.ButtonState.Pressed, device )

					-- Otherwise was it already released?
					elseif state == Input.ButtonState.Released then

						-- Mark it as being just pressed
						self:setButtonState( button, Input.ButtonState.JustPressed, device )

					end

				-- Is the button currently up?
				elseif phase == Input.ButtonPhase.Up then
					
					-- Was it just released?
					if state == Input.ButtonState.JustReleased then

						-- Then mark it as released
						self:setButtonState( button, Input.ButtonState.Released, device )

					-- Otherwise was it pressed or just pressed?
					elseif state == Input.ButtonState.Pressed or state == Input.ButtonState.JustPressed then

						-- Then mark it as just released
						self:setButtonState( button, Input.ButtonState.JustReleased, device )

					end

				end

			-- We don't have a current state
			else

				-- Is the button currently down?
				if phase == Input.ButtonPhase.Down then

					-- Set the button as just pressed
					self:setButtonState( button, Input.ButtonState.JustPressed, device )

				-- Otherwise is the button released?
				elseif phase == Input.ButtonPhase.Up then

					-- Mark it as being just released
					self:setButtonState( button, Input.ButtonState.JustReleased, device )

				end

			end

		end

	end
	
end

--- Destroys this Input library.
function Input:destroy()
	Runtime:removeEventListener( "mouse", self )
	Runtime:removeEventListener( "key", self )
	Runtime:removeEventListener( "axis", self )
end

return Input