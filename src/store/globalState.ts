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
type UserStorages = {
  mainUserId: Maybe<string>
  users: Record<UserId, UserStorage>

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
      mainUserId: "undefined",
      users : {}
    } as UserStorages
  )




  function addUser (id: string, user:{ url: string, accessToken: string }) {
    usersStorages.value.users = {
      [id]: {
        url: user.url,
        accessToken: user.accessToken
      }
    }
  }


  function setMain (id: string) {
    usersStorages.value.mainUserId = id
  }

  function getMain() {
    if(usersStorages.value.mainUserId){
      return usersStorages.value.users[usersStorages.value.mainUserId]
    }else {
      // throw "mainUserId Missing"
    }
  }

  return {
    applicationStorage,
    usersStorages,
    addUser, getMain, setMain


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
