<template>
  <transition-group>
    <transition key="modal">
    <div class="modal dialog ">
      <div class="content">
        <slot />
      </div>
    </div>
    </transition>
    <transition key="modal">
    <div class="modalBackground" @click="handleClickBackground" />
    </transition>
  </transition-group>
</template>

<script lang="ts">
import { ModalControlNames, useRiricaStateStore } from "~/store/globalState";
import { PropType } from "@vue/runtime-core";

export default defineNuxtComponent({
  setup(){
    const { $state } = useRiricaStateStore()

    return {
      state: $state
    }
  },
  props: {
    keyName: {
      type: String as unknown as PropType<ModalControlNames>,
      required: true
    },
    isFireCloseOnClickBackground: {
      type: Boolean,
      default: true
    },
  },
  methods: {
    handleClose(){
      this.state.modalControl[this.keyName] = false
    },
    handleClickBackground(){
      if(!this.isFireCloseOnClickBackground) return
      this.handleClose()
    }
  },
})

// ref https://github.com/misskey-dev/misskey/blob/develop/packages/frontend/src/components/MkModal.vue
</script>

<style lang="scss">
.modalBackground {
  background-color: black;
  opacity: 0.2;
  position: fixed;
  height: 100%;
  width: 100%;
  top:0;
  left: 0;
}


.dialog {
  .content {
    width: 100%;
    height: 100%;
  }

  background-color: white;
  align-items: center;
  justify-content: center;
  width: 500px;
  height: 500px;
  position: fixed;
  top: 0;
  bottom: 0;
  left: 0;
  right: 0;
  margin: auto;
  padding: 32px;
  display: flex;
  z-index: 1;

  @media (max-width: 500px) {
    padding: 16px;
  }

}

</style>
