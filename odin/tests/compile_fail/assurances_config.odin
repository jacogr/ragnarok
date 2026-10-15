// Intentional nominal misuse must be rejected at compilation.
package main
import codec "../../codec"
// Each fixture tests a separate domain boundary without runtime execution.
main :: proc() {
	value := codec.Assurance_Config {
		cores      = codec.Validator_Count(2),
		validators = codec.Core_Count(6),
	}
	_ = value
}
