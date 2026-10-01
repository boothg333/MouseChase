function installVisualExpSwitch(apply)
%INSTALLVISUALEXPSWITCH Let MouseChaseDemo use visual stimuli on this rig.
%   On POPPY-STIM, Documents\MATLAB\+exp\configureSignalsExperiment.m
%   overrides Rigbox's version so that every Signals experiment runs as
%   exp.SignalsExpNoVis (no visual stimuli). This replaces it with
%   tools\poppy-stim\configureSignalsExperiment.m.txt, which does the same
%   for all experiments except those listed in its visualExpDefs (currently
%   MouseChaseDemo), which get the standard exp.SignalsExp.
%
%   INSTALLVISUALEXPSWITCH() shows what would happen; nothing is changed.
%   INSTALLVISUALEXPSWITCH(true) backs up the current override (as
%   configureSignalsExperiment.m.bak_<date>, which MATLAB ignores) and
%   installs the new one. Restart srv.expServer afterwards.
%   To undo: delete the new file and rename the backup back to .m.

if nargin < 1; apply = false; end
source = fullfile(fileparts(mfilename('fullpath')), 'poppy-stim', 'configureSignalsExperiment.m.txt');
target = which('exp.configureSignalsExperiment');
fprintf('Active exp.configureSignalsExperiment: %s\n', target);
assert(~isempty(target) && contains(lower(target), lower(fullfile('Documents', 'MATLAB', '+exp'))), ...
  'installVisualExpSwitch:unexpected', ...
  'Expected the rig override in Documents\\MATLAB\\+exp; found "%s". Not changing anything.', target);
current = fileread(target);
if contains(current, 'visualExpDefs')
  fprintf('The override already has a visualExpDefs list; nothing to do.\n');
  return
end
assert(contains(current, 'SignalsExpNoVis'), 'installVisualExpSwitch:unexpected', ...
  'The current override does not create exp.SignalsExpNoVis; not changing anything.');
fprintf('Will replace it with: %s\n', source);

if ~apply
  fprintf('\nDry run: nothing changed. Call installVisualExpSwitch(true) to install.\n');
  return
end
backup = sprintf('%s.bak_%s', target, datestr(now, 'yyyy-mm-dd_HHMMSS'));
copyfile(target, backup);
fprintf('Backed up to %s\n', backup);
copyfile(source, target, 'f');
clear('exp.configureSignalsExperiment');
rehash path
fprintf('Installed. Restart srv.expServer to use it.\n');
end
