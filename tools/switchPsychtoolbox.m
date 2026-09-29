function switchPsychtoolbox(newRoot)
%SWITCHPSYCHTOOLBOX Swap the Psychtoolbox on the path for this MATLAB session.
%   SWITCHPSYCHTOOLBOX(NEWROOT) removes the currently active Psychtoolbox
%   from the path, unloads its MEX files and adds the Psychtoolbox found in
%   NEWROOT (default 'C:\toolbox\Psychtoolbox'). The change only lasts for
%   this session: restart MATLAB to return to the normal setup.
%
%   Example (on POPPY-STIM, with srv.expServer closed):
%     switchPsychtoolbox('C:\toolbox\Psychtoolbox');
%     touchDiagnostics(40)

if nargin < 1; newRoot = 'C:\toolbox\Psychtoolbox'; end
newRoot = strip(newRoot, 'right', filesep);
assert(exist(fullfile(newRoot, 'PsychBasic'), 'dir') == 7, ...
  'switchPsychtoolbox:notFound', 'No Psychtoolbox found in %s', newRoot);

oldRoot = strip(PsychtoolboxRoot, 'right', filesep);
fprintf('Removing Psychtoolbox %s (%s)\n', PsychtoolboxVersion, oldRoot);
sca;
clear mex %#ok<CLMEX> the old Screen/PsychHID must be unloaded
p =strsplit(path, pathsep);
isOld = strcmpi(p, oldRoot) | startsWith(lower(p), lower([oldRoot filesep]));
if any(isOld); rmpath(p{isOld}); end

newPaths = strsplit(genpath(newRoot), pathsep);
keep = ~cellfun(@isempty, newPaths) & ...
  ~contains(newPaths, [filesep '.git']) & ~contains(newPaths, [filesep '.svn']);
addpath(newPaths{keep});
% The Windows MEX files must shadow any same-named M-file stubs
mexDir = fullfile(newRoot, 'PsychBasic', 'MatlabWindowsFilesR2007a');
if exist(mexDir, 'dir'); addpath(mexDir, '-begin'); end
clear functions %#ok<CLFUNC>
clear global Psychtoolbox % PsychtoolboxVersion caches the version here
rehash path
% Normally run at MATLAB startup; on Windows it puts the GStreamer runtime,
% which Screen depends on, onto the system PATH.
if exist(fullfile(newRoot, 'PsychBasic', 'PsychStartup.m'), 'file')
  PsychStartup;
end
gstRoot = getenv('GSTREAMER_1_0_ROOT_MSVC_X86_64');
if isempty(gstRoot)
  warning('switchPsychtoolbox:noGStreamer', ...
    'GStreamer 64-bit runtime not found; Screen will not load. See ''help GStreamer''.');
else
  fprintf('GStreamer runtime: %s\n', gstRoot);
  % Ensure GStreamer's DLLs (glib etc.) can be found when Screen loads
  gstBin = fullfile(gstRoot, 'bin');
  sysPath = getenv('PATH');
  if ~contains(lower(sysPath), lower(gstBin))
    setenv('PATH', [gstBin pathsep sysPath]);
    fprintf('Added %s to the system PATH for this session\n', gstBin);
  end
  if ~exist(fullfile(gstBin, 'glib-2.0-0.dll'), 'file')
    warning('switchPsychtoolbox:incompleteGStreamer', ...
      'glib-2.0-0.dll not found in %s: GStreamer install may be incomplete.', gstBin);
  end
end
fprintf('Now using Psychtoolbox %s (%s)\n', PsychtoolboxVersion, PsychtoolboxRoot);
fprintf('Screen MEX: %s\n', which('Screen'));
if ~startsWith(lower(which('Screen')), lower(newRoot))
  warning('switchPsychtoolbox:shadowed', ...
    'Screen still resolves outside %s: another Psychtoolbox copy is on the path.', newRoot);
end
end
