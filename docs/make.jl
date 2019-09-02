using Documenter, Tricks

makedocs(;
    modules=[Tricks],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/oxinabox/Tricks.jl/blob/{commit}{path}#L{line}",
    sitename="Tricks.jl",
    authors="Lyndon White",
    assets=String[],
)

deploydocs(;
    repo="github.com/oxinabox/Tricks.jl",
)
