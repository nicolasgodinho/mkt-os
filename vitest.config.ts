import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: 'unit',
          include: [
            'packages/*/src/**/*.test.ts',
            'apps/web/src/**/*.test.{ts,tsx}',
            'scripts/**/*.test.ts',
          ],
          environment: 'node',
        },
      },
      {
        // Protected executable invariants (docs/11). Only TEST_SPEC tasks may edit these files.
        test: {
          name: 'acceptance',
          include: ['tests/acceptance/**/*.test.ts'],
          environment: 'node',
        },
      },
    ],
  },
});
