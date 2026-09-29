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
clear functions %#ok<CLFUNC> drop cached PsychtoolboxRoot/version
rehash path
fprintf('Now using Psychtoolbox %s (%s)\n', PsychtoolboxVersion, PsychtoolboxRoot);
end
