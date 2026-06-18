function plotTouchLog(logFileName)
%PLOTTOUCHLOG Plot touch positions from MouseChaseDemo touch logs.
%   plotTouchLog() prompts for a TouchLog_*.csv file saved by MouseChaseDemo.
%   plotTouchLog(filename) loads the specified CSV and plots X/Y positions over time.
%
%   The CSV file is expected to contain columns: Time, X, Y, and optionally Type.

    if nargin < 1 || isempty(logFileName)
        fileFilter = {'*_MouseChaseTouchLog.csv', 'MouseChase touch logs (*.csv)'; '*.csv', 'All CSV files (*.csv)'};
        [file, path] = uigetfile(fileFilter, 'Select MouseChase touch log file');
        if isequal(file, 0)
            return;
        end
        logFileName = fullfile(path, file);
    end

    if ~isfile(logFileName)
        error('plotTouchLog:FileNotFound', 'Touch log file not found: %s', logFileName);
    end

    logTable = readtable(logFileName);
    requiredVars = {'Time', 'X', 'Y'};
    if ~all(ismember(requiredVars, logTable.Properties.VariableNames))
        error('plotTouchLog:InvalidFile', 'Touch log file must contain Time, X, and Y columns.');
    end

    time = logTable.Time;
    x = logTable.X;
    y = logTable.Y;

    if ismember('Type', logTable.Properties.VariableNames)
        eventType = string(logTable.Type);
    else
        eventType = repmat("touch", height(logTable), 1);
    end

    hasBugPos = all(ismember({'BugX','BugY'}, logTable.Properties.VariableNames));
    if hasBugPos
        bugX = logTable.BugX;
        bugY = logTable.BugY;
        distanceToBug = sqrt((x - bugX).^2 + (y - bugY).^2);
    else
        distanceToBug = nan(height(logTable),1);
    end

    % Subject movement speed based on touch travel between successive touches
    speed = nan(height(logTable),1);
    if numel(time) > 1
        dt = diff(time);
        motion = sqrt(diff(x).^2 + diff(y).^2);
        speed(2:end) = motion ./ dt;
    end

    figure('Name', 'MouseChase Touch Log', 'Color', [1 1 1]);

    subplot(2,2,1);
    plot(time, x, '-o', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'X');
    hold on;
    plot(time, y, '-s', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'Y');
    hold off;
    xlabel('Time (s)');
    ylabel('Position');
    title('Touch positions over time');
    legend('Location', 'best');
    grid on;

    subplot(2,2,2);
    types = unique(eventType, 'stable');
    colors = lines(numel(types));
    hold on;
    for k = 1:numel(types)
        idx = eventType == types(k);
        scatter(time(idx), x(idx), 40, colors(k,:), 'o', 'filled', 'DisplayName', sprintf('X (%s)', types(k)));
        scatter(time(idx), y(idx), 40, colors(k,:), 'x', 'DisplayName', sprintf('Y (%s)', types(k)));
    end
    hold off;
    xlabel('Time (s)');
    ylabel('Position');
    title('Touch events by type');
    legend('Location', 'bestoutside');
    grid on;
    ylim([min([x; y]) - 0.05, max([x; y]) + 0.05]);

    subplot(2,2,3);
    numBins = 40;
    xEdges = linspace(min(x), max(x), numBins+1);
    yEdges = linspace(min(y), max(y), numBins+1);
    heatCounts = histcounts2(x, y, xEdges, yEdges);
    imagesc(xEdges, yEdges, heatCounts');
    set(gca, 'YDir', 'normal');
    colormap hot;
    colorbar;
    xlabel('X position');
    ylabel('Y position');
    title('Touch position heatmap');

    subplot(2,2,4);
    if hasBugPos && any(~isnan(speed))
        scatter(speed, distanceToBug, 40, time, 'filled');
        colorbar;
        xlabel('Subject movement speed (units/s)');
        ylabel('Distance to bug');
        title('Bug distance vs subject movement speed');
        grid on;
    else
        text(0.1, 0.5, 'Bug position data unavailable', 'FontSize', 12);
        axis off;
    end
end
