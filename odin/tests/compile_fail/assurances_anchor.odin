// Intentional nominal misuse must be rejected at compilation.
package main
import codec "../../codec"
// Each fixture tests a separate domain boundary without runtime execution.
main :: proc() {
	value: codec.Assurance_Anchor = codec.Assurance_Signature{}
	_ = value
}
