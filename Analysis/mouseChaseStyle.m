function c = mouseChaseStyle()
%MOUSECHASESTYLE Shared plot palette and axis style for the MouseChase plots.
%   C = MOUSECHASESTYLE() returns colours (RGB rows): mouse/actual blue,
%   chance grey, bug orange, catches aqua, text and axis inks, plus
%   C.seqMap (single-hue blue colormap, light to dark), C.sessionColours(N)
%   (N blues, early light to late dark) and C.style(AX) for axes.

c.mouse = hex('#2a78d6');
c.bug = hex('#eb6834');
c.catch = hex('#1baf7a');
c.primary = hex('#0b0b0b');
c.secondary = hex('#52514e');
c.muted = hex('#898781');
c.axis = hex('#c3c2b7');
c.grid = hex('#e1e0d9');
c.surface = hex('#fcfcfb');
ramp = [hex('#fcfcfb'); hex('#cde2fb'); hex('#86b6ef'); hex('#2a78d6'); hex('#184f95'); hex('#0d366b')];
c.seqMap = interp1(linspace(0, 1, size(ramp, 1)), ramp, linspace(0, 1, 256));
% sessions: from step 250 (light, still visible on white) to step 700
c.sessionColours = @(n) interp1([0 0.5 1], [hex('#86b6ef'); hex('#2a78d6'); hex('#0d366b')], ...
  linspace(0, 1, n)');
c.style = @(ax) styleAxes(ax, c);
end

function rgb = hex(h)
rgb = sscanf(h(2:end), '%2x%2x%2x')' / 255;
end

function styleAxes(ax, c)
set(ax, 'Box', 'off', 'TickDir', 'out', 'XColor', c.secondary, 'YColor', c.secondary, ...
  'GridColor', c.grid, 'GridAlpha', 1, 'FontSize', 9);
ax.Title.FontWeight = 'normal';
ax.Title.FontSize = 10;
ax.Title.Color = c.primary;
end
