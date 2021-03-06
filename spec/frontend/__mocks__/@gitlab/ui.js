export * from '@gitlab/ui';

/**
 * The @gitlab/ui tooltip directive requires awkward and distracting set up in tests
 * for components that use it (e.g., `attachToDocument: true` and `sync: true` passed
 * to the `mount` helper from `vue-test-utils`).
 *
 * This mock decouples those tests from the implementation, removing the need to set
 * them up specially just for these tooltips.
 *
 * Mocking the modules using the full file path allows the mocks to take effect
 * when the modules are imported in this project (`gitlab`) **and** when they
 * are imported internally in `@gitlab/ui`.
 */

jest.mock('@gitlab/ui/dist/directives/tooltip.js', () => ({
  bind() {},
}));

jest.mock('@gitlab/ui/dist/components/base/tooltip/tooltip.js', () => ({
  render(h) {
    return h('div', this.$attrs, this.$slots.default);
  },
}));

jest.mock('@gitlab/ui/dist/components/base/popover/popover.js', () => ({
  props: {
    cssClasses: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  render(h) {
    return h('div', this.$attrs, Object.keys(this.$slots).map(s => this.$slots[s]));
  },
}));
