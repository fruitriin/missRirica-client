import { defineStore } from 'pinia'

// You can name the return value of `defineStore()` anything you want,
// but it's best to use the name of the store and surround it with `use`
// and `Store` (e.g. `useUserStore`, `useCartStore`, `useProductStore`)
// the first argument is a unique id of the store across your application

import { api, Endpoints } from "misskey-js";

type UserId = string
/**
 * ユーザーごとに発生する揮発性のステート
 */
type UserState = {}
type UsersState = Record<UserId, UserState>
import { useStorage } from '@vueuse/core'
import { Maybe } from "~/utils/typeUitls ";
import { APIClient } from "misskey-js/built/api";

/**
 * LocalStorageに保存するユーザー固有データ
 */
type UserStorage = {
  accessToken: string
  url: string
}
type UserStorages = Record<UserId, UserStorage> & {
  mainUserId: Maybe<string>

}


/**
 * ローカルストレージで保存するデータ
 * applicationStorageはMissRirica
 *
 *
 */
export const useStorageStore = () => {

  const applicationStorage = useStorage(
    "applicationStorage", {}
  )
  const usersStorages = useStorage(
    "usersStorage", {
    } as UserStorages
  )

  const usersStoragesModel = {
    state : usersStorages,
    mainUserId: undefined as Maybe<string>,
    client: undefined as Maybe<APIClient>,

    addUser (id: string, user:{ url: string, accessToken: string }){
      this.state.value[id] = {
        url: user.url,
          accessToken: user.accessToken
      }
    },
    setMain (id: string){
      this.state.value.mainUserId = id
    },
    getMain() {
      if(this.state.value.mainUserId){
        return this.state.value[this.state.value.mainUserId]
      }else {
        throw "something wrong"
      }
    },
    noCredentialRequest(serverUrl: string, endpoint :  keyof Endpoints,  params: any){
      const noCredentialClient = new api.APIClient({origin: serverUrl})
      return noCredentialClient.request(endpoint, params)
    },
    request(endpoint: keyof Endpoints, params?: any,  credential?: string) {
      if(this.client) return this.client.request(endpoint, params, credential)
      this.client = new api.APIClient({origin: this.getMain().url, credential: this.getMain().accessToken})
      return this.client.request(endpoint, params, credential)
    }
  }

  return {
    applicationStorage,
    usersStoragesModel
  }
}


export const useStateStore = defineStore('state', {
  state: () => {
    return {
      users: {} as UsersState
    }
  }
})

const riricaState = {
  modalControl: {
    login: false,
    something: true
  }
}

export const useRiricaStateStore = defineStore("riricaState", {
  state: () => riricaState
})

export type ModalControlNames = keyof typeof riricaState.modalControl
