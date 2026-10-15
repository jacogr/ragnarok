// Intentional nominal misuse must be rejected at compilation.
package main
import codec "../../codec"
// Each fixture tests a separate domain boundary without runtime execution.
main :: proc() {
	value: codec.Validator_Index = codec.Core_Count(0)
	_ = value
}
