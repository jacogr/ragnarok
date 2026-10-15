// Intentional nominal-domain misuse must be rejected at compile time.
package main
import codec "../../codec"
import crypto "../../crypto"
// Separate fixtures keep each wrong-domain diagnostic independently observable.
main :: proc() {
	value: crypto.Ed_Signature = crypto.Assurance_Signing_Message{}
	_ = value
}
