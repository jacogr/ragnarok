// Intentional nominal-domain misuse must be rejected at compile time.
package main
import codec "../../codec"
import crypto "../../crypto"
// Separate fixtures keep each wrong-domain diagnostic independently observable.
main :: proc() {
	value: crypto.Assurance_Parent = codec.Assurance_Anchor{}
	_ = value
}
