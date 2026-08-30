'use strict';

const args = process.argv.slice(2);
const patch = process.env.DSH_PORTABLE_PATCH;
const first = args[0]?.toLowerCase();
const defaultOnly = args.includes('--dump-default-config');
const hasProfile = args.some((arg) => arg === '--profile' || arg.startsWith('--profile='));

if (patch && !defaultOnly) {
  if (first === 'web') {
    process.argv[2] = 'web';
    process.argv.splice(3, 0, '--patch', patch);
  } else if (first !== 'plugin' && hasProfile) {
    process.argv.splice(2, 0, '--patch', patch);
  }
}
