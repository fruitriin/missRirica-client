<script lang="ts">
import { useStateStore, useStorageStore } from "~/store/globalState";


export default defineNuxtComponent({
  setup(){
    const {userStorage} = useStorageStore()
    const { $state, } = useStateStore()

    return {
      state: $state,
      userStorage
    }
  },
  mounted(){
    if(!this.userStorage.user){
      this.$router.replace("/login")
    }
  }
})

</script>

<template>
  <div>
    yehhhh
  </div>
</template>

<style lang="scss">

</style>
