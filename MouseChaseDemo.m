function MouseChaseDemo(t, events, params, visStim, inputs, outputs, audio)
% MouseChaseDemo Rigbox Signals experiment definition
%   This expDef is designed to run under Rigbox via srv.expServer. It
%   uses the rig's touchscreen input (`mouseInput`) as a 1D touch proxy,
%   displays a chasing bug stimulus, and saves a subject-specific touch log file.
%
%   Usage:
%     pars = exp.inferParameters(@MouseChaseDemo);
%     pars.subjectName = 'subject1';
%     ref = dat.newExp('test', now, pars);
%     srv.expServer('expRef', ref)

    % Define required parameters and inputs
    subjectNameParam = params.subjectName;
    try
        touchSignal = inputs.mouseInput.skipRepeats();
    catch
        try
            touchSignal = inputs.wheel.skipRepeats();
        catch
            error('MouseChaseDemo:MissingInput', 'No touchscreen or wheel input found in inputs. Expected inputs.mouseInput or inputs.wheel.');
        end
    end
    quitPressed = inputs.keyboard.map(@isQuitKey);

    % Set the experiment stop signal when 'q' is pressed
    events.expStop = quitPressed;

    % Visual elements
    bug = vis.patch(t, 'circle');
    bug.colour = [0 0 0]';
    bug.dims = [6 6]';
    bug.show = true;

    rock = vis.patch(t, 'rectangle');
    rock.colour = [0.7 0.7 0.7]';
    rock.dims = [18 6]';
    rock.azimuth = 0;
    rock.altitude = -8;
    rock.show = true;

    finger = vis.patch(t, 'circle');
    finger.colour = [1 0 0]';
    finger.dims = [3 3]';
    finger.show = true;

    visStim.bug = bug;
    visStim.rock = rock;
    visStim.finger = finger;

    net = t.Node.Net;
    bugX = net.origin('bugX');
    bugY = net.origin('bugY');
    fingerX = net.origin('fingerX');
    fingerY = net.origin('fingerY');

    bug.azimuth = bugX;
    bug.altitude = bugY;
    finger.azimuth = fingerX;
    finger.altitude = fingerY;

    bugPos = [0; 0];
    bugVel = [0; 0];
    currentTouch = [0; 0];
    lastTouch = [0; 0];
    lastTouchTime = 0;
    touchLog = struct('Time', {}, 'X', {}, 'Y', {}, 'BugX', {}, 'BugY', {}, 'SubjectSpeed', {});
    hasSaved = false;

    touchSignal.onValue(@logTouch);
    events.expStop.onValue(@(~)saveTouchLog());
    t.onValue(@(~)updateBug());
    events.expStart.onValue(@(~)assertSubjectName());

    function logTouch(value)
        if isempty(events.expStart.Node.CurrValue)
            return;
        end

        time = t.Node.CurrValue;
        touchX = parseTouchValue(value);
        if isempty(touchX)
            return;
        end

        touchX = max(min(touchX, 12), -12);
        currentTouch = [touchX; 0];

        subjectSpeed = nan;
        if lastTouchTime > 0
            dt = time - lastTouchTime;
            if dt > 0
                subjectSpeed = norm(currentTouch - lastTouch) / dt;
            end
        end
        lastTouchTime = time;
        lastTouch = currentTouch;

        newEntry.Time = time;
        newEntry.X = currentTouch(1);
        newEntry.Y = currentTouch(2);
        newEntry.BugX = bugPos(1);
        newEntry.BugY = bugPos(2);
        newEntry.SubjectSpeed = subjectSpeed;
        touchLog(end+1) = newEntry; %#ok<AGROW>

        fingerX.post(currentTouch(1));
        fingerY.post(currentTouch(2));
    end

    function updateBug()
        time = t.Node.CurrValue;
        persistent lastTime
        if isempty(lastTime)
            lastTime = time;
        end

        dt = time - lastTime;
        if dt <= 0 || dt > 0.1
            dt = 0.016;
        end
        lastTime = time;

        target = currentTouch;
        dist = norm(target - bugPos);
        if dist > 0.1
            evadeDir = (bugPos - target) / dist;
            desiredSpeed = min(20, 4 + 20 * exp(-dist));
            desiredVel = evadeDir * desiredSpeed;
        else
            desiredVel = randn(2,1) * 0.5;
        end

        bugVel = bugVel + (desiredVel - bugVel) * min(1, 8*dt);
        bugPos = bugPos + bugVel * dt;
        bugPos = max(min(bugPos, [12; 12]), [-12; -12]);

        bugX.post(bugPos(1));
        bugY.post(bugPos(2));
    end

    function saveTouchLog()
        if hasSaved
            return;
        end
        hasSaved = true;

        if isempty(touchLog)
            return;
        end

        subjectName = strtrim(subjectNameParam.Node.CurrValue);
        if isempty(subjectName)
            subjectName = 'unknown';
        end

        safeSubject = regexprep(subjectName, '[<>:\"/\\|?*]', '_');
        subjectDir = fullfile('C:\LocalExpData', safeSubject);
        if ~exist(subjectDir, 'dir')
            mkdir(subjectDir);
        end

        dateStr = datestr(now, 'yyyy-mm-dd');
        filePattern = fullfile(subjectDir, sprintf('%s_*_%s_MouseChaseTouchLog.csv', dateStr, safeSubject));
        existingFiles = dir(filePattern);
        runIndex = numel(existingFiles) + 1;
        logFileName = sprintf('%s_%d_%s_MouseChaseTouchLog.csv', dateStr, runIndex, safeSubject);
        logFilePath = fullfile(subjectDir, logFileName);

        try
            writetable(struct2table(touchLog), logFilePath);
            fprintf('Touch log saved to %s\n', logFilePath);
        catch ME
            warning(ME.identifier, '%s', ME.message);
        end
    end

    function touchX = parseTouchValue(value)
        touchX = [];
        if isempty(value)
            return;
        end
        if isnumeric(value) && numel(value) >= 1
            touchX = value(1);
            return;
        end
        if ischar(value) || isstring(value)
            num = str2double(value);
            if ~isnan(num)
                touchX = num;
                return;
            end
        end
        if iscell(value)
            for ii = 1:numel(value)
                touchX = parseTouchValue(value{ii});
                if ~isempty(touchX)
                    return;
                end
            end
        end
    end

    function assertSubjectName()
        subjectName = strtrim(subjectNameParam.Node.CurrValue);
        assert(~isempty(subjectName), 'MouseChaseDemo:MissingSubjectName', ...
            'Subject name parameter must be specified before the experiment starts.');
    end

    function tf = isQuitKey(keyValue)
        tf = false;
        if isempty(keyValue)
            return;
        end
        if ischar(keyValue) || isstring(keyValue)
            tf = any(lower(string(keyValue)) == 'q');
            return;
        end
        if iscell(keyValue)
            tf = any(cellfun(@(v) isQuitKey(v), keyValue));
        end
    end
end
