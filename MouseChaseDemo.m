function MouseChaseDemo()
    % Main function that runs the whole demo
    
    % Create a gray, full-screen figure
    fig = figure('Name', 'Mouse Chase Demo', ...
        'Color', [0.5 0.5 0.5], ...
        'Units', 'normalized', ...
        'Position', [0.1 0.1 0.8 0.8], ...
        'MenuBar', 'none', ...
        'ToolBar', 'none');
    
    % Force MATLAB to draw the figure so we can get its true pixel dimensions
    drawnow; 
    figPos = getpixelposition(fig);
    xMax = figPos(3) / figPos(4);
    yMax = 1;
    
    % Create axes for drawing and lock the aspect ratio
    ax = axes(fig, 'Position', [0 0 1 1], ...
        'XLim', [0 xMax], 'YLim', [0 yMax], ...
        'Color', [0.5 0.5 0.5], ...
        'DataAspectRatio', [1 1 1]);
        
    % Lock limits manually so the patches don't stretch the screen when out of bounds
    ax.XLimMode = 'manual';
    ax.YLimMode = 'manual';
    axis off;
    
    % Define the triangular rock in the middle
    rockX = [0.4, 0.6, 0.5] * xMax;
    rockY = [0.4, 0.4, 0.6] * yMax;
    
    % Initialize finger and bug state at the center of the arena
    fingerPos = [xMax/2, yMax/2];
    prevFingerPos = fingerPos;
    bugPos = [xMax/2, yMax/2];
    bugVel = [0, 0];
    wanderAngle = rand() * 2 * pi;
    heading = wanderAngle; % Track heading explicitly
    
    % Define bug geometry
    bugLength = 0.04; % Semi-major axis
    bugWidth = 0.015; % Semi-minor axis
    theta = linspace(0, 2*pi, 20); % Points around the ellipse
    
    % Assign callbacks to capture screen touches and drags
    fig.WindowButtonDownFcn = @(~, ~) updateFinger(ax);
    fig.WindowButtonMotionFcn = @(~, ~) updateFinger(ax);
    
    % Draw the bug FIRST so it sits at the bottom of the visual stack
    bugPatch = patch(ax, 'XData', [], 'YData', [], 'FaceColor', 'k', 'EdgeColor', 'none');
    
    % Draw the rock SECOND so it sits on top of the bug and occludes it
    rockPatch = patch(ax, 'XData', rockX, 'YData', rockY, 'FaceColor', [0.7 0.7 0.7], 'EdgeColor', 'none');
    
    % Run the animation loop
    tic;
    while ishandle(fig)
        dt = toc;
        tic;
        
        % Cap dt to avoid huge jumps if the system lags
        if dt > 0.1
            dt = 0.016; 
        end
        
        % Constantly update xMax in case the window is resized during the demo
        figPos = getpixelposition(fig);
        xMax = figPos(3) / figPos(4);
        ax.XLim = [0 xMax];
        
        % Calculate finger speed
        fingerSpeed = norm(fingerPos - prevFingerPos) / dt;
        prevFingerPos = fingerPos;
        
        % Update physics and behavior
        [bugPos, bugVel, wanderAngle, heading] = moveBug(bugPos, bugVel, fingerPos, fingerSpeed, wanderAngle, heading, dt, xMax, yMax, rockX, rockY);
        
        % Get rotated coordinates and update the patch
        [x, y] = getRotatedOval(bugPos, bugLength, bugWidth, heading, theta);
        bugPatch.XData = x;
        bugPatch.YData = y;
        
        drawnow limitrate;
    end
    
    % --- Nested callback function to update finger coordinates ---
    function updateFinger(targetAx)
        cp = targetAx.CurrentPoint;
        % Constrain coordinates between 0 and the dynamic limits
        x = max(0, min(xMax, cp(1,1)));
        y = max(0, min(yMax, cp(1,2)));
        fingerPos = [x, y];
    end
end % End of MouseChaseDemo

function [newPos, newVel, newWanderAngle, newHeading] = moveBug(pos, vel, fingerPos, fingerSpeed, wanderAngle, heading, dt, xMax, yMax, rockX, rockY)
    % Moves the bug using non-holonomic kinematics (no sideways skidding)
    
    % Check if bug is hidden (under rock or in crevice)
    isUnderRock = inpolygon(pos(1), pos(2), rockX, rockY);
    isOffScreen = pos(1) < 0 || pos(1) > xMax || pos(2) < 0 || pos(2) > yMax;
    isHidden = isUnderRock || isOffScreen;
    
    visualRange = 0.7; 
    motionThreshold = 0.15; 
    dist = norm(fingerPos - pos);
    
    % Evade only if visible and threatened
    isEvading = ~isHidden && (dist < visualRange) && (dist > 0) && (fingerSpeed > motionThreshold);
    
    if isEvading
        % Evade!
        direction = (pos - fingerPos) / dist;
        desiredHeading = atan2(direction(2), direction(1));
        thrust = (visualRange - dist) * 35; % Scale up as it gets closer
        thrust = min(thrust, 20); % Cap maximum acceleration
        newWanderAngle = desiredHeading; % Keep wander angle synced
    else
        % Wander!
        newWanderAngle = wanderAngle + randn() * 3 * dt; % Slowly drift the desired heading
        desiredHeading = newWanderAngle;
        thrust = 0.8; % Steady, slow forward walk
    end
    
    % Update the heading smoothly toward the desired heading
    deltaAngle = mod(desiredHeading - heading + pi, 2*pi) - pi;
    maxTurnRate = 8; % Radians per second
    turnStep = sign(deltaAngle) * min(abs(deltaAngle), maxTurnRate * dt);
    newHeading = heading + turnStep;
    
    % Apply thrust strictly in the direction the bug is facing
    headingVec = [cos(newHeading), sin(newHeading)];
    appliedForce = headingVec * thrust;
    
    % Apply physics (friction and integration)
    friction = 6;
    newVel = vel + appliedForce * dt - friction * vel * dt;
    
    % Eliminate lateral skidding by projecting velocity onto the heading axis
    forwardSpeed = max(0, dot(newVel, headingVec)); 
    newVel = forwardSpeed * headingVec;
    
    newPos = pos + newVel * dt;
    
    % Constrain bug to an invisible outer bounding box to mimic deep wall crevices
    outerPad = 0.15; 
    hitOuterWall = false;
    
    if newPos(1) < -outerPad
        newPos(1) = -outerPad; hitOuterWall = true;
    elseif newPos(1) > xMax + outerPad
        newPos(1) = xMax + outerPad; hitOuterWall = true;
    end
    
    if newPos(2) < -outerPad
        newPos(2) = -outerPad; hitOuterWall = true;
    elseif newPos(2) > yMax + outerPad
        newPos(2) = yMax + outerPad; hitOuterWall = true;
    end
    
    if hitOuterWall
        % Bug has hit the absolute limit inside the crevice, force it to turn around
        centerDir = [xMax/2, yMax/2] - newPos;
        newWanderAngle = atan2(centerDir(2), centerDir(1));
        
        % Kill momentum to force a realistic turning animation inside the wall
        newVel = [0, 0];
    end
end % End of moveBug

function [x, y] = getRotatedOval(center, len, wid, heading, theta)
    % Calculates the coordinates of a rotated ellipse
    
    % Base unrotated coordinates
    xb = len * cos(theta);
    yb = wid * sin(theta);
    
    % Rotation matrix
    R = [cos(heading), -sin(heading); 
         sin(heading),  cos(heading)];
     
    % Apply rotation
    coords = R * [xb; yb];
    
    % Translate to the bug's center position
    x = coords(1, :) + center(1);
    y = coords(2, :) + center(2);
end % End of getRotatedOval