function T = list()
%MOUSECHASEENV.LIST Table of the saved environments.
dir_ = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'MouseChaseEnvironments');
files = dir(fullfile(dir_, '*.mat'));
id = {}; floorType = {}; rectangles = []; ellipses = []; created = {}; description = {};
for k = 1:numel(files)
  s = builtin('load', fullfile(dir_, files(k).name), 'env');
  e = s.env;
  id{end+1, 1} = e.id; %#ok<AGROW>
  floorType{end+1, 1} = e.floor.type; %#ok<AGROW>
  rectangles(end+1, 1) = sum(strcmp({e.objects.shape}, 'rectangle')); %#ok<AGROW>
  ellipses(end+1, 1) = sum(strcmp({e.objects.shape}, 'ellipse')); %#ok<AGROW>
  created{end+1, 1} = e.created; %#ok<AGROW>
  description{end+1, 1} = e.description; %#ok<AGROW>
end
T = table(id, floorType, rectangles, ellipses, created, description);
if nargout == 0; disp(T); clear T; end
end
