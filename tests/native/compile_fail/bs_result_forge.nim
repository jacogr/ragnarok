## Callers cannot forge completed native imports.
import ../../../src/bandersnatch/bandersnatch
discard BsResult[BsKey](status: BsError.None, completed: default(BsKey))
