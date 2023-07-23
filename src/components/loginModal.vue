<script lang="ts">
export default defineNuxtComponent({
  data(){
    return {
      serverUrl: "",
      userId: "",
      password: "",
      accessToken: "",
    }
  },
  methods:{
    login(){
      // ログインリクエスト投げて問題なければstoreへ入れる
    }
  }
})

</script>
<template>
  <Teleport to="body">
    <Modal @close="$emit('close')">
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
