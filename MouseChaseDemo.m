function MouseChaseDemo(t, events, p, visStim, inputs, outputs, ~)
%MOUSECHASEDEMO Signals experiment definition for the Mouse Chase task.
%   The subject controls the cursor and attempts to catch a wandering bug.
%   Cursor position is sampled from the mouse signal, while the bug state is
%   advanced by a Signals scan at a fixed update rate.

%% Experiment and arena constants
updateTime = 0.03;
arenaSz = [180 105];
arenaColor = [1 1 1];
rockCenter = [0 0];
rockSz = [36 21];
outerPad = 4;

targetCatches = p.targetCatches;
bugColor = p.bugColor;
rockColor = p.rockColor;
catchRadius = p.catchRadius;

% inputs.wheel is the mouse-linked input in the Signals experiment setup.
% Its value is not used as a wheel displacement: each update prompts a fresh
% cursor-position sample, allowing the cursor to act as a two-dimensional
% behavioural input.
mouse = inputs.wheel;
cursor = mouse.map(@(~) getCursorPosition(arenaSz));
tUpdate = skipRepeats(t - mod(t, updateTime));
cursorAtUpdate = cursor.at(tUpdate);

%% World state
gameDataInit = struct;
gameDataInit.bugPos = [0 0];
gameDataInit.bugVel = [0 0];
gameDataInit.wanderAngle = rand() * 2 * pi;
gameDataInit.heading = gameDataInit.wanderAngle;
gameDataInit.cursorPos = [0 0];
gameDataInit.distanceToBug = inf;
gameDataInit.arenaSz = arenaSz;
gameDataInit.rockCenter = rockCenter;
gameDataInit.rockSz = rockSz;
gameDataInit.outerPad = outerPad;

gameData = cursorAtUpdate.scan(@updateGame, gameDataInit).subscriptable;

  function gameData = updateGame(gameData, cursorPos)
    cursorSpeed = norm(cursorPos - gameData.cursorPos) / updateTime;
    [gameData.bugPos, gameData.bugVel, gameData.wanderAngle, ...
      gameData.heading] = moveBug(...
      gameData.bugPos, gameData.bugVel, cursorPos, cursorSpeed, ...
      gameData.wanderAngle, gameData.heading, updateTime, ...
      gameData.arenaSz, gameData.rockCenter, gameData.rockSz, ...
      gameData.outerPad);
    gameData.cursorPos = cursorPos;
    gameData.distanceToBug = norm(cursorPos - gameData.bugPos);
  end

bugX = gameData.bugPos(1);
bugY = gameData.bugPos(2);
bugHeading = gameData.heading;
cursorX = gameData.cursorPos(1);
cursorY = gameData.cursorPos(2);
distanceToBug = gameData.distanceToBug;

% A catch is armed once per trial, after a short grace period, and fires only
% when the cursor enters the catch radius. The Signals runner then advances
% to the next trial.
caught = distanceToBug <= catchRadius;
catchArm = events.newTrial.delay(1);
catchEvent = catchArm.setTrigger(caught);
events.endTrial = catchEvent;

catchCount = catchEvent.scan(@plus, 0);
events.catch = catchEvent;
events.catchCount = catchCount;
events.cursorX = cursorX;
events.cursorY = cursorY;
events.bugX = bugX;
events.bugY = bugY;
events.distanceToBug = distanceToBug;
outputs.catch = catchEvent.then(1);

endGame = catchCount >= targetCatches;
events.expStop = endGame.then(1);

%% Visual stimuli
arena = vis.patch(t, 'rectangle');
arena.dims = arenaSz;
arena.azimuth = 0;
arena.altitude = 0;
arena.colour = arenaColor;
arena.show = true;

rock = vis.patch(t, 'rectangle');
rock.dims = rockSz;
rock.azimuth = rockCenter(1);
rock.altitude = rockCenter(2);
rock.colour = rockColor;
rock.show = true;

bug = vis.patch(t, 'circle');
bug.dims = [p.bugDiameter p.bugDiameter];
bug.azimuth = bugX;
bug.altitude = bugY;
bug.orientation = rad2deg(bugHeading);
bug.colour = bugColor;
bug.show = true;

% The cursor is represented by a small cross so the subject can see the
% position used by the task, without relying on the operating-system cursor.
cursorStim = vis.patch(t, 'cross');
cursorStim.dims = [2 2];
cursorStim.azimuth = cursorX;
cursorStim.altitude = cursorY;
cursorStim.colour = [0 0 1];
cursorStim.show = true;

visStim.arena = arena;
visStim.rock = rock;
visStim.bug = bug;
visStim.cursor = cursorStim;

%% Experimenter parameters
try
  p.targetCatches = 5;
  p.bugColor = [0 0 0]';
  p.rockColor = [0.7 0.7 0.7]';
  p.catchRadius = 3;
  p.bugDiameter = 2;
catch
end

  function pos = getCursorPosition(arenaSize)
    screens = Screen('Screens');
    [screenWidth, screenHeight] = Screen('WindowSize', max(screens));
    [pixelX, pixelY] = GetMouse();
    pos = [pixelX / screenWidth * arenaSize(1) - arenaSize(1) / 2,...
      arenaSize(2) / 2 - pixelY / screenHeight * arenaSize(2)];
  end

end

function [newPos, newVel, newWanderAngle, newHeading] = moveBug(...
    pos, vel, cursorPos, cursorSpeed, wanderAngle, heading, dt, ...
    arenaSz, rockCenter, rockSz, outerPad)
%MOVEBUG Advance the bug using non-holonomic kinematics.

isUnderRock = isInsideRectangle(pos, rockCenter, rockSz);
isOffScreen = pos(1) < -arenaSz(1) / 2 || ...
    pos(1) > arenaSz(1) / 2 || pos(2) < -arenaSz(2) / 2 || ...
    pos(2) > arenaSz(2) / 2;
isHidden = isUnderRock || isOffScreen;

visualRange = 0.5;
motionThreshold = 0.25;
dist = norm(cursorPos - pos);
isEvading = ~isHidden && dist < visualRange && dist > 0 && ...
    cursorSpeed > motionThreshold;

if isEvading
  direction = (pos - cursorPos) / dist;
  desiredHeading = atan2(direction(2), direction(1));
  thrust = min((visualRange - dist) * 12, 6);
  newWanderAngle = desiredHeading;
else
  newWanderAngle = wanderAngle + randn() * 2 * dt;
  desiredHeading = newWanderAngle;
  thrust = 0.4;
end

deltaAngle = mod(desiredHeading - heading + pi, 2 * pi) - pi;
maxTurnRate = 6;
turnStep = sign(deltaAngle) * min(abs(deltaAngle), maxTurnRate * dt);
newHeading = heading + turnStep;

headingVec = [cos(newHeading), sin(newHeading)];
newVel = vel + headingVec * thrust * dt - 6 * vel * dt;
forwardSpeed = max(0, dot(newVel, headingVec));
maxSpeed = 1.2;
newVel = min(forwardSpeed, maxSpeed) * headingVec;
newPos = pos + newVel * dt;

hitOuterWall = false;
if newPos(1) < -arenaSz(1) / 2 - outerPad
  newPos(1) = -arenaSz(1) / 2 - outerPad;
  hitOuterWall = true;
elseif newPos(1) > arenaSz(1) / 2 + outerPad
  newPos(1) = arenaSz(1) / 2 + outerPad;
  hitOuterWall = true;
end
if newPos(2) < -arenaSz(2) / 2 - outerPad
  newPos(2) = -arenaSz(2) / 2 - outerPad;
  hitOuterWall = true;
elseif newPos(2) > arenaSz(2) / 2 + outerPad
  newPos(2) = arenaSz(2) / 2 + outerPad;
  hitOuterWall = true;
end

if hitOuterWall
  centerDir = -newPos;
  returnHeading = atan2(centerDir(2), centerDir(1));
  newWanderAngle = returnHeading;
  newHeading = returnHeading;
  returnSpeed = min(maxSpeed, max(forwardSpeed, 0.4));
  newVel = returnSpeed * [cos(newHeading), sin(newHeading)];
end
end

function inside = isInsideRectangle(pos, center, dims)
inside = abs(pos(1) - center(1)) <= dims(1) / 2 && ...
    abs(pos(2) - center(2)) <= dims(2) / 2;
end
