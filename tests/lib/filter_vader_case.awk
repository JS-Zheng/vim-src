BEGIN {
  keep_current = 0
  current_kind = ""
  case_count = 0
  if (case_file != "") {
    while ((getline pattern < case_file) > 0) {
      case_patterns[++case_count] = pattern
    }
    close(case_file)
  } else {
    case_count = split(case_specs, case_patterns, "\n")
  }
}

function is_header(line) {
  if (line ~ /^Include([[:space:]]*\([^)]*\))?[[:space:]]*:[[:space:]]*[^[:space:]]/) {
    return 1
  }
  return line ~ /^(Before|After|Given|Execute|Do|Then|Expect|Include)([[:space:](].*)?[:;][[:space:]]*$/
}

function header_kind(line,   kind) {
  if (line ~ /^Include([[:space:]]*\([^)]*\))?[[:space:]]*:/) {
    return "Include"
  }
  kind = line
  sub(/[[:space:](].*$/, "", kind)
  sub(/[:;]$/, "", kind)
  return kind
}

function is_global_kind(kind) {
  return kind == "Before" || kind == "After" || kind == "Given" || kind == "Include"
}

function case_matches(line,   i) {
  if (case_count == 0) {
    return 1
  }

  for (i = 1; i <= case_count; i++) {
    if (case_patterns[i] != "" && index(line, case_patterns[i]) > 0) {
      return 1
    }
  }

  return 0
}

{
  if (is_header($0)) {
    kind = header_kind($0)

    if (is_global_kind(kind)) {
      keep_current = 1
      current_kind = "global"
      print
      next
    }

    if (kind == "Execute" || kind == "Do") {
      keep_current = case_matches($0)
      current_kind = "case"
      if (keep_current) {
        print
      }
      next
    }

    if (kind == "Then" || kind == "Expect") {
      if (current_kind == "case" && keep_current) {
        print
      } else {
        keep_current = 0
      }
      current_kind = "case-tail"
      next
    }
  }

  if (keep_current) {
    print
  }
}
