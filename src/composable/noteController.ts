import { entities } from "misskey-js";
import { userStore } from "~/store/UserStore";

export function useNoteController(note: entities.Note) {
  const { api, $i } = userStore();

  const isRenote =
    note.renote != null &&
    note.text == null &&
    note.fileIds.length === 0 &&
    note.poll == null;

  const isMyRenote = note.userId === $i.id;

  const appearNote = isRenote ? note.renote : note;
  // TODO
  function reply(text: string) {
    api
      .request("notes/create", {
        replyId: note.id,
        text,
      })
      .then();
  }

  // stub
  function react() {}
  function undoReact() {}

  return {
    isRenote,
    appearNote,
    isMyRenote,

    reply,
    react,
    undoReact,
  };
}
