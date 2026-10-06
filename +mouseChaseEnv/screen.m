function scr = screen()
%MOUSECHASEENV.SCREEN Touchscreen geometry used to build and preview
%   environments. Keep in line with the rig's hardware.mat (touchScreen,
%   see tools/configureTouchScreenRig.m and tools/setSyncSquare.m).
%     dimsCm       visible screen area [w h], cm
%     extentCm     area a floor image covers (1.1 x the screen: overscan)
%     floorPx      longest side of rendered floor images, px (kept small)
%     blockedCm    areas the mouse can't reach, [xmin ymin xmax ymax] per row
%                  (the box over the photodiode square, bottom-right)
%     creviceCm    how far past the edge the bug can hide
%     maxPerShape  hiding objects of each shape the task can draw
scr.dimsCm = [37.6 30.1];
scr.extentCm = 1.1 * scr.dimsCm;
scr.floorPx = 256;
box = 2.2;
scr.blockedCm = [scr.dimsCm(1)/2 - box, -scr.dimsCm(2)/2, scr.dimsCm(1)/2, -scr.dimsCm(2)/2 + box];
scr.creviceCm = 4.5;
scr.maxPerShape = 6;
end
