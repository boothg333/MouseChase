function [fakeDir, cleanup] = makeFakePtb()
%MAKEFAKEPTB Temporary stand-ins for the Psychtoolbox touch functions.
%   [FAKEDIR, CLEANUP] = MAKEFAKEPTB() writes minimal fake versions of
%   Screen, GetSecs and the TouchQueue functions to a new temporary folder
%   and puts it at the top of the path, so MouseChaseDemo can run without a
%   touchscreen. They read the global SIM (SIM.time, SIM.queue of touch
%   events, SIM.released). The folder is removed from the path and deleted
%   when CLEANUP is cleared or goes out of scope.
%
%   The fakes are generated rather than stored in the repo on purpose: a
%   Screen.m anywhere on a rig's path would shadow the real Psychtoolbox.

removeStaleFakes();
fakeDir = tempname;
mkdir(fakeDir);
files = {
  'MOUSECHASE_FAKE_PTB.txt', {'Temporary fake Psychtoolbox functions; safe to delete.'}
  'Screen.m', {
    'function out = Screen(cmd, varargin)'
    'switch cmd'
    '  case ''Windows'', out = 10;'
    '  case ''WindowKind'', out = 1;'
    '  otherwise, error(''fake Screen: %s'', cmd);'
    'end'
    'end'}
  'GetSecs.m', {
    'function t = GetSecs()'
    'global SIM'
    't = SIM.time;'
    'end'}
  'GetTouchDeviceIndices.m', {
    'function dev = GetTouchDeviceIndices(varargin)'
    'dev = 1;'
    'end'}
  'TouchQueueCreate.m', {'function TouchQueueCreate(varargin)', 'end'}
  'TouchQueueStart.m', {'function TouchQueueStart(varargin)', 'end'}
  'TouchQueueStop.m', {'function TouchQueueStop(varargin)', 'end'}
  'TouchQueueRelease.m', {
    'function TouchQueueRelease(varargin)'
    'global SIM'
    'SIM.released = SIM.released + 1;'
    'end'}
  'TouchEventAvail.m', {
    'function n = TouchEventAvail(varargin)'
    'global SIM'
    'n = numel(SIM.queue);'
    'end'}
  'TouchEventGet.m', {
    'function evt = TouchEventGet(varargin)'
    'global SIM'
    'evt = SIM.queue(1);'
    'SIM.queue(1) = [];'
    'end'}
  };
for k = 1:size(files, 1)
  fid = fopen(fullfile(fakeDir, files{k,1}), 'w');
  fprintf(fid, '%s\n', files{k,2}{:});
  fclose(fid);
end
addpath(fakeDir, '-begin');
cleanup = onCleanup(@() removeFakes(fakeDir));
end

function removeFakes(fakeDir)
if contains([pathsep path pathsep], [pathsep fakeDir pathsep]); rmpath(fakeDir); end
if exist(fakeDir, 'dir'); rmdir(fakeDir, 's'); end
end

function removeStaleFakes()
% Fake folders left on the path by an earlier run that crashed
p = strsplit(path, pathsep);
for k = 1:numel(p)
  if exist(fullfile(p{k}, 'MOUSECHASE_FAKE_PTB.txt'), 'file')
    removeFakes(p{k});
  end
end
end
