<template>
  <div class="tab-menu">
    <button class="button nav _button" @click="drawerMenuShowing = true">
      <Menu2Icon />

      <span v-if="menuIndicated" class="indicator"><CircleIcon /> ></span>
    </button>
    <button
      class="button home _button"
      @click="
        mainRouter.currentRoute.value.name === 'index'
          ? top()
          : mainRouter.push('/')
      "
    >
      <HomeIcon />
    </button>
    <button
      class="button notifications _button"
      @click="mainRouter.push('/my/notifications')"
    >
      <BellIcon />
      <span v-if="$i?.hasUnreadNotification" class="indicator"
        ><CircleIcon
      /></span>
    </button>
    <button class="button widget _button" @click="widgetsShowing = true">
      <LayersUnionIcon />
    </button>
    <button class="button post _button" @click="os.post()">
      <PencilIcon />
    </button>
  </div>
</template>

<script lang="ts">
import {
  CircleIcon,
  Menu2Icon,
  HomeIcon,
  BellIcon,
  LayersUnionIcon,
  PencilIcon,
} from "vue-tabler-icons";
export default defineComponent({
  components: {
    CircleIcon,
    Menu2Icon,
    HomeIcon,
    BellIcon,
    LayersUnionIcon,
    PencilIcon,
  },
});
</script>

<style lang="scss" scoped>
.tab-menu {
  position: fixed;
  z-index: 1000;
  bottom: 0;
  left: 0;
  padding: 16px 16px calc(env(safe-area-inset-bottom, 0px) + 16px) 16px;
  display: flex;
  width: 100%;
  box-sizing: border-box;
  -webkit-backdrop-filter: var(--blur, blur(32px));
  backdrop-filter: var(--blur, blur(32px));
  background-color: var(--header);
  border-top: solid 0.5px var(--divider);

  > .button {
    position: relative;
    flex: 1;
    padding: 0;
    margin: auto;
    height: 64px;
    border-radius: 8px;
    background: var(--panel);
    color: var(--fg);

    &:not(:last-child) {
      margin-right: 12px;
    }

    @media (max-width: 400px) {
      height: 60px;

      &:not(:last-child) {
        margin-right: 8px;
      }
    }

    &:hover {
      background: var(--X2);
    }

    > .indicator {
      position: absolute;
      top: 0;
      left: 0;
      color: var(--indicator);
      font-size: 16px;
      animation: blink 1s infinite;
    }

    &:first-child {
      margin-left: 0;
    }

    &:last-child {
      margin-right: 0;
    }

    > * {
      font-size: 20px;
    }

    &:disabled {
      cursor: default;

      > * {
        opacity: 0.5;
      }
    }
  }
}
</style>
