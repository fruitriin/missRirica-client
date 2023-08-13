<script lang="ts">
import { useRiricaStateStore, useStorageStore } from "~/store/globalState";
import { APIClient } from "misskey-js/built/api";

export default defineNuxtComponent({
  setup(){
    const { userStorage } =  useStorageStore()
    const { modalControl } = useRiricaStateStore()
    return {  modalControl, userStorage }
  },
  data(){
    return {
      serverUrl: "",
      userId: "",
      password: "",
      accessToken: "",
    }
  },
  methods:{
    async login(){
      // ログインリクエスト投げて問題なければstoreへ入れる
      const client = new APIClient({ origin: this.serverUrl, credential: this.accessToken})
      const result = await client.request("i").catch((reason) => {
        alert(reason)
      })
      if(!result) {
        alert(result)
        return
      }

      this.userStorage.addUser(result.id, {url: this.serverUrl, accessToken: this.accessToken})
      this.userStorage.setMain(result.id)

      // このNextTickがないとlocalStorageへの反映前にインスタンスが消える
      await nextTick()
      this.modalControl.login = false
    }
  }
})

</script>
<template>
  <Teleport to="body">
    <Modal key-name="login">
      <div>
        <div>
        サーバーURL
        <input v-model="serverUrl" />
        </div>
        <div>
        アクセストークン
        <input v-model="accessToken">
        </div>
        <div>
          ユーザーID
          <input v-model="userId" />

        </div>
        <div>
        パスワード
        <input v-model="password" type="password" />
        </div>


        <button @click="login">ログイン</button>
      </div>
    </Modal>

  </Teleport>
</template>

<style lang="scss">

</style>
