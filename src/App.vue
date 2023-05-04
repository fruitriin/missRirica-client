<template>
  <div>
    hi
  </div>
</template>

<script>
export default {
  mounted() {

    const misskeyV13 = document.createElement("script")
    misskeyV13.setAttribute("src", "misskey-v13/app.js")
    misskeyV13.setAttribute("type", "module")
    const misskeyV13Style = document.createElement("link")
    misskeyV13Style.setAttribute("rel", "stylesheet" )
    misskeyV13Style.setAttribute("href", "misskey-v13/init.css")
    document.head.appendChild(misskeyV13)
    document.head.appendChild(misskeyV13Style)
  }
}
</script>
