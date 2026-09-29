%STARTMOUSECHASESERVER Start the stimulus server for MouseChaseDemo.
%   On the stimulus PC (POPPY-STIM), in MATLAB:
%     run C:\Users\Experiment\Documents\Github\MouseChase\startMouseChaseServer
%
%   Switches this MATLAB session to Psychtoolbox 3.0.18 (needed to read the
%   multi-touch overlay) and starts srv.expServer. Run it once per MATLAB
%   session; the server then handles any number of experiments from mc.
%   Other experiments keep using the rig's normal Psychtoolbox: restart
%   MATLAB and start srv.expServer the usual way.

ptb318Root = 'C:\toolbox\Psychtoolbox';
addpath(fullfile(fileparts(mfilename('fullpath')), 'tools'));
if startsWith(lower(PsychtoolboxRoot), lower(ptb318Root))
  fprintf('Already using Psychtoolbox %s\n', PsychtoolboxVersion);
else
  switchPsychtoolbox(ptb318Root);
end
clear ptb318Root
srv.expServer
