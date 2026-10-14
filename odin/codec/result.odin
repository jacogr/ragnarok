package codec

// Allocation-free tagged outcome: T owns completed data; E owns only the failure reason.
// There is no nil state, and success fields cannot be read from the union itself.
Codec_Result :: union($T: typeid, $E: typeid) #no_nil {
	E,
	T,
}

// Inspect the discriminator without accessing success data; None is the status convention for success.
error_of :: proc(outcome: Codec_Result($T, $E)) -> E {
	switch item in outcome {
	case T:
		return E.None // Only the completed-data alternative has successful status.
	case E:
		if item == E.None {return E.Uninitialized} 	// A fabricated empty failure cannot masquerade as the success alternative.
		return item // Failed operations expose their reason without default payload fields.
	}
	unreachable() // The no-nil union exhausts both alternatives above.
}

// Extract completed data after checking the result or switching on its success type.
// The checked union assertion fails on API misuse; it never fabricates a zero value on decoder failure.
success_of :: proc(outcome: Codec_Result($T, $E)) -> T {return outcome.(T)}
