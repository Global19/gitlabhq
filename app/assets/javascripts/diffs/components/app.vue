<script>
import { mapState, mapGetters, mapActions } from 'vuex';
import { GlLoadingIcon, GlButtonGroup, GlButton } from '@gitlab/ui';
import Mousetrap from 'mousetrap';
import { __ } from '~/locale';
import createFlash from '~/flash';
import PanelResizer from '~/vue_shared/components/panel_resizer.vue';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { isSingleViewStyle } from '~/helpers/diffs_helper';
import { updateHistory } from '~/lib/utils/url_utility';
import eventHub from '../../notes/event_hub';
import CompareVersions from './compare_versions.vue';
import DiffFile from './diff_file.vue';
import NoChanges from './no_changes.vue';
import HiddenFilesWarning from './hidden_files_warning.vue';
import CommitWidget from './commit_widget.vue';
import TreeList from './tree_list.vue';
import {
  TREE_LIST_WIDTH_STORAGE_KEY,
  INITIAL_TREE_WIDTH,
  MIN_TREE_WIDTH,
  MAX_TREE_WIDTH,
  TREE_HIDE_STATS_WIDTH,
  MR_TREE_SHOW_KEY,
  CENTERED_LIMITED_CONTAINER_CLASSES,
} from '../constants';

export default {
  name: 'DiffsApp',
  components: {
    CompareVersions,
    DiffFile,
    NoChanges,
    HiddenFilesWarning,
    CommitWidget,
    TreeList,
    GlLoadingIcon,
    PanelResizer,
    GlButtonGroup,
    GlButton,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    endpoint: {
      type: String,
      required: true,
    },
    endpointMetadata: {
      type: String,
      required: true,
    },
    endpointBatch: {
      type: String,
      required: true,
    },
    endpointCoverage: {
      type: String,
      required: false,
      default: '',
    },
    projectPath: {
      type: String,
      required: true,
    },
    shouldShow: {
      type: Boolean,
      required: false,
      default: false,
    },
    currentUser: {
      type: Object,
      required: true,
    },
    helpPagePath: {
      type: String,
      required: false,
      default: '',
    },
    changesEmptyStateIllustration: {
      type: String,
      required: false,
      default: '',
    },
    isFluidLayout: {
      type: Boolean,
      required: false,
      default: false,
    },
    dismissEndpoint: {
      type: String,
      required: false,
      default: '',
    },
    showSuggestPopover: {
      type: Boolean,
      required: false,
      default: false,
    },
    viewDiffsFileByFile: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    const treeWidth =
      parseInt(localStorage.getItem(TREE_LIST_WIDTH_STORAGE_KEY), 10) || INITIAL_TREE_WIDTH;

    return {
      treeWidth,
      diffFilesLength: 0,
    };
  },
  computed: {
    ...mapState({
      isLoading: state => state.diffs.isLoading,
      isBatchLoading: state => state.diffs.isBatchLoading,
      diffFiles: state => state.diffs.diffFiles,
      diffViewType: state => state.diffs.diffViewType,
      mergeRequestDiffs: state => state.diffs.mergeRequestDiffs,
      mergeRequestDiff: state => state.diffs.mergeRequestDiff,
      commit: state => state.diffs.commit,
      renderOverflowWarning: state => state.diffs.renderOverflowWarning,
      numTotalFiles: state => state.diffs.realSize,
      numVisibleFiles: state => state.diffs.size,
      plainDiffPath: state => state.diffs.plainDiffPath,
      emailPatchPath: state => state.diffs.emailPatchPath,
      retrievingBatches: state => state.diffs.retrievingBatches,
    }),
    ...mapState('diffs', ['showTreeList', 'isLoading', 'startVersion', 'currentDiffFileId']),
    ...mapGetters('diffs', ['isParallelView', 'currentDiffIndex']),
    ...mapGetters(['isNotesFetched', 'getNoteableData']),
    diffs() {
      if (!this.viewDiffsFileByFile) {
        return this.diffFiles;
      }

      return this.diffFiles.filter((file, i) => {
        return file.file_hash === this.currentDiffFileId || (i === 0 && !this.currentDiffFileId);
      });
    },
    canCurrentUserFork() {
      return this.currentUser.can_fork === true && this.currentUser.can_create_merge_request;
    },
    renderDiffFiles() {
      return (
        this.diffFiles.length > 0 ||
        (this.startVersion &&
          this.startVersion.version_index === this.mergeRequestDiff.version_index)
      );
    },
    hideFileStats() {
      return this.treeWidth <= TREE_HIDE_STATS_WIDTH;
    },
    isLimitedContainer() {
      return !this.showTreeList && !this.isParallelView && !this.isFluidLayout;
    },
  },
  watch: {
    commit(newCommit, oldCommit) {
      const commitChangedAfterRender = newCommit && !this.isLoading;
      const commitIsDifferent = oldCommit && newCommit.id !== oldCommit.id;
      const url = window?.location ? String(window.location) : '';

      if (commitChangedAfterRender && commitIsDifferent) {
        updateHistory({
          title: document.title,
          url: url.replace(oldCommit.id, newCommit.id),
        });
        this.refetchDiffData();
        this.adjustView();
      }
    },
    diffViewType() {
      if (this.needsReload() || this.needsFirstLoad()) {
        this.refetchDiffData();
      }
      this.adjustView();
    },
    shouldShow() {
      // When the shouldShow property changed to true, the route is rendered for the first time
      // and if we have the isLoading as true this means we didn't fetch the data
      if (this.isLoading) {
        this.fetchData();
      }

      this.adjustView();
    },
    isLoading: 'adjustView',
    showTreeList: 'adjustView',
  },
  mounted() {
    this.setBaseConfig({
      endpoint: this.endpoint,
      endpointMetadata: this.endpointMetadata,
      endpointBatch: this.endpointBatch,
      endpointCoverage: this.endpointCoverage,
      projectPath: this.projectPath,
      dismissEndpoint: this.dismissEndpoint,
      showSuggestPopover: this.showSuggestPopover,
      useSingleDiffStyle: this.glFeatures.singleMrDiffView,
      viewDiffsFileByFile: this.viewDiffsFileByFile,
    });

    if (this.shouldShow) {
      this.fetchData();
    }

    const id = window?.location?.hash;

    if (id && id.indexOf('#note') !== 0) {
      this.setHighlightedRow(
        id
          .split('diff-content')
          .pop()
          .slice(1),
      );
    }
  },
  created() {
    this.adjustView();
    eventHub.$once('fetchDiffData', this.fetchData);
    eventHub.$on('refetchDiffData', this.refetchDiffData);
    this.CENTERED_LIMITED_CONTAINER_CLASSES = CENTERED_LIMITED_CONTAINER_CLASSES;

    this.unwatchDiscussions = this.$watch(
      () => `${this.diffFiles.length}:${this.$store.state.notes.discussions.length}`,
      () => this.setDiscussions(),
    );

    this.unwatchRetrievingBatches = this.$watch(
      () => `${this.retrievingBatches}:${this.$store.state.notes.discussions.length}`,
      () => {
        if (!this.retrievingBatches && this.$store.state.notes.discussions.length) {
          this.unwatchDiscussions();
          this.unwatchRetrievingBatches();
        }
      },
    );
  },
  beforeDestroy() {
    eventHub.$off('fetchDiffData', this.fetchData);
    eventHub.$off('refetchDiffData', this.refetchDiffData);
    this.removeEventListeners();
  },
  methods: {
    ...mapActions(['startTaskList']),
    ...mapActions('diffs', [
      'moveToNeighboringCommit',
      'setBaseConfig',
      'fetchDiffFiles',
      'fetchDiffFilesMeta',
      'fetchDiffFilesBatch',
      'fetchCoverageFiles',
      'startRenderDiffsQueue',
      'assignDiscussionsToDiff',
      'setHighlightedRow',
      'cacheTreeListWidth',
      'scrollToFile',
      'toggleShowTreeList',
      'navigateToDiffFileIndex',
    ]),
    refetchDiffData() {
      this.fetchData(false);
    },
    startDiffRendering() {
      requestIdleCallback(
        () => {
          this.startRenderDiffsQueue();
        },
        { timeout: 1000 },
      );
    },
    needsReload() {
      return (
        this.glFeatures.singleMrDiffView &&
        this.diffFiles.length &&
        isSingleViewStyle(this.diffFiles[0])
      );
    },
    needsFirstLoad() {
      return this.glFeatures.singleMrDiffView && !this.diffFiles.length;
    },
    fetchData(toggleTree = true) {
      if (this.glFeatures.diffsBatchLoad) {
        this.fetchDiffFilesMeta()
          .then(({ real_size }) => {
            this.diffFilesLength = parseInt(real_size, 10);
            if (toggleTree) this.hideTreeListIfJustOneFile();

            this.startDiffRendering();
          })
          .catch(() => {
            createFlash(__('Something went wrong on our end. Please try again!'));
          });

        this.fetchDiffFilesBatch()
          .then(() => {
            // Guarantee the discussions are assigned after the batch finishes.
            // Just watching the length of the discussions or the diff files
            // isn't enough, because with split diff loading, neither will
            // change when loading the other half of the diff files.
            this.setDiscussions();
          })
          .then(() => this.startDiffRendering())
          .catch(() => {
            createFlash(__('Something went wrong on our end. Please try again!'));
          });
      } else {
        this.fetchDiffFiles()
          .then(({ real_size }) => {
            this.diffFilesLength = parseInt(real_size, 10);
            if (toggleTree) {
              this.hideTreeListIfJustOneFile();
            }

            requestIdleCallback(
              () => {
                this.setDiscussions();
                this.startRenderDiffsQueue();
              },
              { timeout: 1000 },
            );
          })
          .catch(() => {
            createFlash(__('Something went wrong on our end. Please try again!'));
          });
      }

      if (this.endpointCoverage) {
        this.fetchCoverageFiles();
      }

      if (!this.isNotesFetched) {
        eventHub.$emit('fetchNotesData');
      }
    },
    setDiscussions() {
      requestIdleCallback(
        () =>
          this.assignDiscussionsToDiff()
            .then(this.$nextTick)
            .then(this.startTaskList),
        { timeout: 1000 },
      );
    },
    adjustView() {
      if (this.shouldShow) {
        this.$nextTick(() => {
          this.setEventListeners();
        });
      } else {
        this.removeEventListeners();
      }
    },
    setEventListeners() {
      Mousetrap.bind(['[', 'k', ']', 'j'], (e, combo) => {
        switch (combo) {
          case '[':
          case 'k':
            this.jumpToFile(-1);
            break;
          case ']':
          case 'j':
            this.jumpToFile(+1);
            break;
          default:
            break;
        }
      });

      if (this.commit && this.glFeatures.mrCommitNeighborNav) {
        Mousetrap.bind('c', () => this.moveToNeighboringCommit({ direction: 'next' }));
        Mousetrap.bind('x', () => this.moveToNeighboringCommit({ direction: 'previous' }));
      }
    },
    removeEventListeners() {
      Mousetrap.unbind(['[', 'k', ']', 'j']);
      Mousetrap.unbind('c');
      Mousetrap.unbind('x');
    },
    jumpToFile(step) {
      const targetIndex = this.currentDiffIndex + step;
      if (targetIndex >= 0 && targetIndex < this.diffFiles.length) {
        this.scrollToFile(this.diffFiles[targetIndex].file_path);
      }
    },
    hideTreeListIfJustOneFile() {
      const storedTreeShow = localStorage.getItem(MR_TREE_SHOW_KEY);

      if ((storedTreeShow === null && this.diffFiles.length <= 1) || storedTreeShow === 'false') {
        this.toggleShowTreeList(false);
      }
    },
  },
  minTreeWidth: MIN_TREE_WIDTH,
  maxTreeWidth: MAX_TREE_WIDTH,
};
</script>

<template>
  <div v-show="shouldShow">
    <div v-if="isLoading" class="loading"><gl-loading-icon size="lg" /></div>
    <div v-else id="diffs" :class="{ active: shouldShow }" class="diffs tab-pane">
      <compare-versions
        :merge-request-diffs="mergeRequestDiffs"
        :is-limited-container="isLimitedContainer"
        :diff-files-count-text="numTotalFiles"
      />

      <hidden-files-warning
        v-if="renderOverflowWarning"
        :visible="numVisibleFiles"
        :total="numTotalFiles"
        :plain-diff-path="plainDiffPath"
        :email-patch-path="emailPatchPath"
      />

      <div
        :data-can-create-note="getNoteableData.current_user.can_create_note"
        class="files d-flex"
      >
        <div
          v-if="showTreeList"
          :style="{ width: `${treeWidth}px` }"
          class="diff-tree-list js-diff-tree-list mr-3"
        >
          <panel-resizer
            :size.sync="treeWidth"
            :start-size="treeWidth"
            :min-size="$options.minTreeWidth"
            :max-size="$options.maxTreeWidth"
            side="right"
            @resize-end="cacheTreeListWidth"
          />
          <tree-list :hide-file-stats="hideFileStats" />
        </div>
        <div
          class="diff-files-holder"
          :class="{
            [CENTERED_LIMITED_CONTAINER_CLASSES]: isLimitedContainer,
          }"
        >
          <commit-widget v-if="commit" :commit="commit" :collapsible="false" />
          <div v-if="isBatchLoading" class="loading"><gl-loading-icon size="lg" /></div>
          <template v-else-if="renderDiffFiles">
            <diff-file
              v-for="file in diffs"
              :key="file.newPath"
              :file="file"
              :help-page-path="helpPagePath"
              :can-current-user-fork="canCurrentUserFork"
              :view-diffs-file-by-file="viewDiffsFileByFile"
            />
            <div v-if="viewDiffsFileByFile" class="d-flex gl-justify-content-center">
              <gl-button-group>
                <gl-button
                  :disabled="currentDiffIndex === 0"
                  data-testid="singleFilePrevious"
                  @click="navigateToDiffFileIndex(currentDiffIndex - 1)"
                >
                  {{ __('Prev') }}
                </gl-button>
                <gl-button
                  :disabled="currentDiffIndex === diffFiles.length - 1"
                  data-testid="singleFileNext"
                  @click="navigateToDiffFileIndex(currentDiffIndex + 1)"
                >
                  {{ __('Next') }}
                </gl-button>
              </gl-button-group>
            </div>
          </template>
          <no-changes v-else :changes-empty-state-illustration="changesEmptyStateIllustration" />
        </div>
      </div>
    </div>
  </div>
</template>
