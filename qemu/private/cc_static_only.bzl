"""Rule to strip shared library artifacts from CcInfo.

When BCR deps (like openssl, glib) provide both .a and .so files,
rules_foreign_cc stages both into $EXT_BUILD_DEPS/lib/. Autotools/libtool
then prefers the .so, producing binaries with unwanted RPATH dependencies.

This rule wraps a cc_library and re-exports its CcInfo with only static
library artifacts, forcing downstream consumers to link statically.
"""

def _cc_static_only_impl(ctx):
    cc_info = ctx.attr.dep[CcInfo]

    new_linker_inputs = []
    for li in cc_info.linking_context.linker_inputs.to_list():
        new_libs = []
        for lib in li.libraries:
            if lib.static_library == None and lib.pic_static_library == None:
                continue
            new_libs.append(
                cc_common.create_library_to_link(
                    actions = ctx.actions,
                    static_library = lib.static_library,
                    pic_static_library = lib.pic_static_library,
                    alwayslink = lib.alwayslink,
                ),
            )
        new_linker_inputs.append(
            cc_common.create_linker_input(
                owner = li.owner,
                libraries = depset(new_libs),
                user_link_flags = depset(li.user_link_flags),
                additional_inputs = depset(li.additional_inputs),
            ),
        )

    return [CcInfo(
        compilation_context = cc_info.compilation_context,
        linking_context = cc_common.create_linking_context(
            linker_inputs = depset(new_linker_inputs),
        ),
    )]

cc_static_only = rule(
    implementation = _cc_static_only_impl,
    attrs = {
        "dep": attr.label(mandatory = True, providers = [CcInfo]),
    },
    provides = [CcInfo],
)
