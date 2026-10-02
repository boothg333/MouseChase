function examples(overwrite)
%MOUSECHASEENV.EXAMPLES Build and save a few example environments.
%   MOUSECHASEENV.EXAMPLES() saves (without replacing existing ones):
%     rocks3           grey floor, three rocks spread over the screen
%     checkerLeaves    checkerboard floor, a log and two leaves
%     orientationCheck dark top / light bottom, small rock in the top-left
%                      corner: on the touchscreen it must look like
%                      mouseChaseEnv.preview('orientationCheck')
%   MOUSECHASEENV.EXAMPLES(true) replaces them.
if nargin < 1; overwrite = false; end
rock = [0.65 0.65 0.65];

env = mouseChaseEnv.create('rocks3', 'Grey floor, three rocks');
env = mouseChaseEnv.addObject(env, 'ellipse', [-10 5], [7 4.5], 15, rock);
env = mouseChaseEnv.addObject(env, 'ellipse', [8 7], [5 3.5], -30, rock);
env = mouseChaseEnv.addObject(env, 'rectangle', [2 -7], [6 4], 10, rock);
trySave(env, overwrite);

env = mouseChaseEnv.create('checkerLeaves', 'Checkerboard floor, a log and two leaves');
env = mouseChaseEnv.setFloor(env, 'checker', 'squareCm', 2.5, ...
  'colours', [0.42 0.42 0.42; 0.56 0.56 0.56]);
env = mouseChaseEnv.addObject(env, 'rectangle', [0 0], [12 3], 25, [0.45 0.33 0.2]);
env = mouseChaseEnv.addObject(env, 'ellipse', [-11 -6], [5 2.5], -40, [0.3 0.5 0.25]);
env = mouseChaseEnv.addObject(env, 'ellipse', [10 6], [5 2.5], 60, [0.3 0.5 0.25]);
trySave(env, overwrite);

env = mouseChaseEnv.create('orientationCheck', ...
  'Floor dark at the top, light at the bottom; small rock top-left');
env = mouseChaseEnv.setFloor(env, 'gradient', 'colours', [0.75 0.75 0.75; 0.25 0.25 0.25], 'angle', 90);
env = mouseChaseEnv.addObject(env, 'rectangle', [-15 12], [4 2], 0, [0.9 0.2 0.2]);
trySave(env, overwrite);
end

function trySave(env, overwrite)
try
  mouseChaseEnv.save(env, overwrite);
catch ex
  if strcmp(ex.identifier, 'mouseChaseEnv:exists')
    fprintf('%s already exists; kept it.\n', env.id);
  else
    rethrow(ex);
  end
end
end
