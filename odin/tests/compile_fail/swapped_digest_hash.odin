// Deliberately reject a raw/wrong-domain digest field at compile time.
package bad
import codec "../../codec"
// Nominal domain mistakes must fail before any codec can run.
main :: proc() {
	wrong: codec.Payload_Hash
	value: codec.Work_Digest
	value.code_hash = wrong
}
