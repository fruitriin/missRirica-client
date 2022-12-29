<template>
  <div class="note" :class="{ renote: isRenote }">
    <div v-if="appearNote.pinned" class="info">
      <i class="ti ti-pin"></i> i18n.ts.pinnedNote
    </div>
    <div v-if="appearNote._prId_" class="info">
      <i class="fas fa-bullhorn"></i> i18n.ts.promotion
      <button class="_textButton hide" @click="readPromo()">
        i18n.ts.hideThisNote <i class="ti ti-x"></i>
      </button>
    </div>
    <div v-if="appearNote._featuredId_" class="info">
      <i class="ti ti-bolt"></i> i18n.ts.featured
    </div>
    <div v-if="isRenote" class="renote">
      <avater class="avatar" :user="note.user" />
      <i class="ti ti-repeat" />
      i18n.ts.renotedBy

      <nuxt-link>
        <UserName :user="appearNote.user"></UserName>
      </nuxt-link>
      <div class="info">
        <button ref="renoteTime" class="_button time" @click="showRenoteMenu()">
          <i v-if="isMyRenote" class="ti ti-dots dropdownIcon"></i>
          {{ note.createdAt }}
          <!--          <MkTime :time="note.createdAt" />-->
        </button>
      </div>
    </div>
    <article class="article">
      <Avater :user="appearNote.user" />
      <div class="main">
        <UserName :user="appearNote.user" />
        <!--        <XNoteHeader class="header" :note="appearNote" :mini="true"/>-->
        <InstanceTicker class="ticker" :instance="appearNote.user.instance" />

        <div class="body">
          <p v-if="appearNote.cw != null" class="cw">
            {{ appearNote.cw }}
          </p>
          <div
            v-show="appearNote.cw == null || showContent"
            class="content"
            :class="{ collapsed, isLong }"
          >
            <div class="text">
              <span v-if="appearNote.isHidden" style="opacity: 0.5"
                >( i18n.ts.private
              </span>
              <!--              todo -->
              <nuxt-link
                v-if="appearNote.replyId"
                :href="`/notes/${appearNote.replyId}`"
              >
                <i class="ti ti-arrow-back-up"></i>
              </nuxt-link>
              <p>{{ appearNote.text }}</p>
              <p>{{ appearNote.emojis }}</p>

              <a v-if="appearNote.renote != null" class="rp">RN:</a>
              <div v-if="translating || translation" class="translation">
                <MkLoading v-if="translating" mini />
                <div v-else class="translated">
                  <b
                    >{{ $t("translatedFrom", { x: translation.sourceLang }) }}:
                  </b>
                  <p>
                    {{ translat }}
                  </p>
                  <Mfm
                    :text="translation.text"
                    :author="appearNote.user"
                    :i="$i"
                    :custom-emojis="appearNote.emojis"
                  />
                </div>
              </div>
            </div>
            <div v-if="appearNote.files.length > 0" class="files">
              添付ファイルあり
              <!--              <XMediaList :media-list="appearNote.files"/>-->
            </div>
            <div>投票あり</div>
            <!--            <XPoll v-if="appearNote.poll" ref="pollViewer" :note="appearNote" class="poll"/>-->
            <!--            <MkUrlPreview v-for="url in urls" :key="url" :url="url" :compact="true" :detail="false" class="url-preview"/>-->
            <div v-if="appearNote.renote" class="renote">
              {{ appearNote.renote.text }}
            </div>
            <button
              v-if="isLong && collapsed"
              class="fade _button"
              @click="collapsed = false"
            >
              <span>{{ i18n.ts.showMore }}</span>
            </button>
            <button
              v-else-if="isLong && !collapsed"
              class="showLess _button"
              @click="collapsed = true"
            >
              <span> i18n.ts.showLess </span>
            </button>
          </div>
          <a
            v-if="appearNote.channel && !inChannel"
            class="channel"
            :to="`/channels/${appearNote.channel.id}`"
            ><i class="ti ti-device-tv"></i> {{ appearNote.channel.name }}</a
          >
        </div>
        <footer class="footer">
          <!--          <XReactionsViewer ref="reactionsViewer" :note="appearNote" />-->
          <button class="button _button" @click="reply()">
            <i class="ti ti-arrow-back-up"></i>
            <p v-if="appearNote.repliesCount > 0" class="count">
              {{ appearNote.repliesCount }}
            </p>
          </button>
          <!--          <XRenoteButton-->
          <!--            ref="renoteButton"-->
          <!--            class="button"-->
          <!--            :note="appearNote"-->
          <!--            :count="appearNote.renoteCount"-->
          <!--          />-->
          <button
            v-if="appearNote.myReaction == null"
            ref="reactButton"
            class="button _button"
            @click="react()"
          >
            <i class="ti ti-plus"></i>
          </button>
          <button
            v-if="appearNote.myReaction != null"
            ref="reactButton"
            class="button _button reacted"
            @click="undoReact(appearNote)"
          >
            <i class="ti ti-minus"></i>
          </button>
          <button class="button _button" @click="menu()">
            <i class="ti ti-dots"></i>
          </button>
        </footer>
      </div>
    </article>
  </div>
</template>

<script lang="ts">
import { entities } from "misskey-js";
import { computed, PropType } from "vue";
import { useNoteController } from "~/composable/noteController";

export default {
  setup(props: Props) {
    const { isRenote, appearNote, isMyRenote } = useNoteController(props.note);
    return {
      isRenote,
      appearNote,
      isMyRenote,
    };
  },
  name: "note",
  components: {},
  props: {
    note: {
      type: Object as PropType<entities.Note>,
      required: true,
    },
  },
  methods: {
    readPromo() {},
  },
  computed: {},
};
</script>

<style scoped lang="scss">
.note {
  position: relative;
  transition: box-shadow 0.1s ease;
  font-size: 1.05em;
  overflow: clip;
  contain: content;

  // これらの指定はパフォーマンス向上には有効だが、ノートの高さは一定でないため、
  // 下の方までスクロールすると上のノートの高さがここで決め打ちされたものに変化し、表示しているノートの位置が変わってしまう
  // ノートがマウントされたときに自身の高さを取得し contain-intrinsic-size を設定しなおせばほぼ解決できそうだが、
  // 今度はその処理自体がパフォーマンス低下の原因にならないか懸念される。また、被リアクションでも高さは変化するため、やはり多少のズレは生じる
  // 一度レンダリングされた要素はブラウザがよしなにサイズを覚えておいてくれるような実装になるまで待った方が良さそう(なるのか？)
  //content-visibility: auto;
  //contain-intrinsic-size: 0 128px;

  &:focus-visible {
    outline: none;

    &:after {
      content: "";
      pointer-events: none;
      display: block;
      position: absolute;
      z-index: 10;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      margin: auto;
      width: calc(100% - 8px);
      height: calc(100% - 8px);
      border: dashed 1px var(--focus);
      border-radius: var(--radius);
      box-sizing: border-box;
    }
  }

  &:hover > .article > .main > .footer > .button {
    opacity: 1;
  }

  > .info {
    display: flex;
    align-items: center;
    padding: 16px 32px 8px 32px;
    line-height: 24px;
    font-size: 90%;
    white-space: pre;
    color: #d28a3f;

    > i {
      margin-right: 4px;
    }

    > .hide {
      margin-left: auto;
      color: inherit;
    }
  }

  > .info + .article {
    padding-top: 8px;
  }

  > .reply-to {
    opacity: 0.7;
    padding-bottom: 0;
  }

  > .renote {
    display: flex;
    align-items: center;
    padding: 16px 32px 8px 32px;
    line-height: 28px;
    white-space: pre;
    color: var(--renote);

    > .avatar {
      flex-shrink: 0;
      display: inline-block;
      width: 28px;
      height: 28px;
      margin: 0 8px 0 0;
      border-radius: 6px;
    }

    > i {
      margin-right: 4px;
    }

    > span {
      overflow: hidden;
      flex-shrink: 1;
      text-overflow: ellipsis;
      white-space: nowrap;

      > .name {
        font-weight: bold;
      }
    }

    > .info {
      margin-left: auto;
      font-size: 0.9em;

      > .time {
        flex-shrink: 0;
        color: inherit;

        > .dropdownIcon {
          margin-right: 4px;
        }
      }
    }
  }

  > .renote + .article {
    padding-top: 8px;
  }

  > .article {
    display: flex;
    padding: 28px 32px 18px;

    > .avatar {
      flex-shrink: 0;
      display: block;
      margin: 0 14px 8px 0;
      width: 58px;
      height: 58px;
      position: sticky;
      top: calc(22px + var(--stickyTop, 0px));
      left: 0;
    }

    > .main {
      flex: 1;
      min-width: 0;

      > .body {
        container-type: inline-size;

        > .cw {
          cursor: default;
          display: block;
          margin: 0;
          padding: 0;
          overflow-wrap: break-word;

          > .text {
            margin-right: 8px;
          }
        }

        > .content {
          &.isLong {
            > .showLess {
              width: 100%;
              margin-top: 1em;
              position: sticky;
              bottom: 1em;

              > span {
                display: inline-block;
                background: var(--popup);
                padding: 6px 10px;
                font-size: 0.8em;
                border-radius: 999px;
                box-shadow: 0 2px 6px rgb(0 0 0 / 20%);
              }
            }
          }

          &.collapsed {
            position: relative;
            max-height: 9em;
            overflow: hidden;

            > .fade {
              display: block;
              position: absolute;
              bottom: 0;
              left: 0;
              width: 100%;
              height: 64px;
              background: linear-gradient(0deg, var(--panel), var(--X15));

              > span {
                display: inline-block;
                background: var(--panel);
                padding: 6px 10px;
                font-size: 0.8em;
                border-radius: 999px;
                box-shadow: 0 2px 6px rgb(0 0 0 / 20%);
              }

              &:hover {
                > span {
                  background: var(--panelHighlight);
                }
              }
            }
          }

          > .text {
            overflow-wrap: break-word;

            > .reply {
              color: var(--accent);
              margin-right: 0.5em;
            }

            > .rp {
              margin-left: 4px;
              font-style: oblique;
              color: var(--renote);
            }

            > .translation {
              border: solid 0.5px var(--divider);
              border-radius: var(--radius);
              padding: 12px;
              margin-top: 8px;
            }
          }

          > .url-preview {
            margin-top: 8px;
          }

          > .poll {
            font-size: 80%;
          }

          > .renote {
            padding: 8px 0;

            > * {
              padding: 16px;
              border: dashed 1px var(--renote);
              border-radius: 8px;
            }
          }
        }

        > .channel {
          opacity: 0.7;
          font-size: 80%;
        }
      }

      > .footer {
        > .button {
          margin: 0;
          padding: 8px;
          opacity: 0.7;

          &:not(:last-child) {
            margin-right: 28px;
          }

          &:hover {
            color: var(--fgHighlighted);
          }

          > .count {
            display: inline;
            margin: 0 0 0 8px;
            opacity: 0.7;
          }

          &.reacted {
            color: var(--accent);
          }
        }
      }
    }
  }

  > .reply {
    border-top: solid 0.5px var(--divider);
  }
}

@container (max-width: 500px) {
  .tkcbzcuz {
    font-size: 0.9em;

    > .article {
      > .avatar {
        width: 50px;
        height: 50px;
      }
    }
  }
}

@container (max-width: 450px) {
  .tkcbzcuz {
    > .renote {
      padding: 8px 16px 0 16px;
    }

    > .info {
      padding: 8px 16px 0 16px;
    }

    > .article {
      padding: 14px 16px 9px;

      > .avatar {
        margin: 0 10px 8px 0;
        width: 46px;
        height: 46px;
        top: calc(14px + var(--stickyTop, 0px));
      }
    }
  }
}

@container (max-width: 350px) {
  .tkcbzcuz {
    > .article {
      > .main {
        > .footer {
          > .button {
            &:not(:last-child) {
              margin-right: 18px;
            }
          }
        }
      }
    }
  }
}

@container (max-width: 300px) {
  .tkcbzcuz {
    > .article {
      > .avatar {
        width: 44px;
        height: 44px;
      }

      > .main {
        > .footer {
          > .button {
            &:not(:last-child) {
              margin-right: 12px;
            }
          }
        }
      }
    }
  }
}

.muted {
  padding: 8px;
  text-align: center;
  opacity: 0.7;
}
</style>
