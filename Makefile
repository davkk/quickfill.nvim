.PHONY: test install-test-deps

test:
	eval $$(luarocks --lua-version 5.1 path --bin) && busted --lua=nlua -v

install-test-deps:
	luarocks --lua-version 5.1 install --local busted
	luarocks --lua-version 5.1 install --local nlua
