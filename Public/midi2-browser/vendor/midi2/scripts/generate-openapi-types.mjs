#!/usr/bin/env node
/**
 * Codegen: emit TypeScript types and runtime type guards from midi2.full.openapi.json.
 *
 * The OpenAPI document uses `#/$defs/...` references; we normalize these to
 * `#/components/schemas/...` and generate one guard per schema.
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..");
const midi2JsRoot = path.resolve(repoRoot, "midi2.js");
const specPath = path.resolve(repoRoot, "midi2.full.openapi.json");
const outputPath = path.resolve(midi2JsRoot, "src/generated/openapi-types.ts");

const spec = JSON.parse(fs.readFileSync(specPath, "utf8"));
const schemas = spec?.components?.schemas;
if (!schemas) {
  throw new Error("OpenAPI spec missing components.schemas");
}

function sanitizeName(raw) {
  const cleaned = raw.replace(/[^A-Za-z0-9_]/g, "_");
  if (/^[A-Za-z_]/.test(cleaned)) return cleaned;
  return `T_${cleaned}`;
}

function refName(ref) {
  const parts = ref.split("/");
  return parts[parts.length - 1];
}

function refType(ref) {
  return sanitizeName(refName(ref));
}

function stripOneOf(schema) {
  const copy = { ...schema };
  delete copy.oneOf;
  return copy;
}

function hasObjectShape(schema) {
  return Boolean(schema.type === "object" || schema.properties || schema.required || schema.additionalProperties !== undefined);
}

function schemaToType(schema) {
  if ("$ref" in schema) {
    return refType(schema.$ref);
  }
  if (schema.oneOf) {
    const base = hasObjectShape(schema) ? schemaToType(stripOneOf(schema)) : null;
    const union = schema.oneOf.map(s => schemaToType(resolveRef(s)));
    if (base && base !== "{}") {
      return union.map(u => `(${base} & ${u})`).join(" | ");
    }
    return union.join(" | ");
  }
  if (schema.enum) {
    return schema.enum.map(v => JSON.stringify(v)).join(" | ");
  }
  if ("const" in schema) {
    return JSON.stringify(schema.const);
  }
  const type = schema.type;
  if (type === "object" || schema.properties || schema.additionalProperties !== undefined) {
    const props = schema.properties ?? {};
    const required = new Set(schema.required ?? []);
    const segments = ["{"]; // open object literal
    for (const [propName, propSchema] of Object.entries(props)) {
      const optional = required.has(propName) ? "" : "?";
      segments.push(`  ${JSON.stringify(propName)}${optional}: ${schemaToType(resolveRef(propSchema))};`);
    }
    if (schema.additionalProperties) {
      if (schema.additionalProperties === true) {
        segments.push(`  [key: string]: unknown;`);
      } else {
        segments.push(`  [key: string]: ${schemaToType(resolveRef(schema.additionalProperties))};`);
      }
    }
    segments.push("}");
    return segments.join("\n");
    }
  if (type === "array") {
    const itemType = schema.items ? schemaToType(resolveRef(schema.items)) : "unknown";
    return `${itemType}[]`;
  }
  if (type === "integer" || type === "number") {
    return "number";
  }
  if (type === "string") {
    return "string";
  }
  if (type === "boolean") {
    return "boolean";
  }
  return "unknown";
}

function guardFor(schema, valueExpr, extraKeys = []) {
  if ("$ref" in schema) {
    return `is${refType(schema.$ref)}(${valueExpr})`;
  }
  if (schema.oneOf) {
    const variantKeys = Array.from(
      new Set(
        schema.oneOf.flatMap(candidate => {
          const resolved = resolveRef(candidate);
          return resolved && typeof resolved === "object" && resolved.properties ? Object.keys(resolved.properties) : [];
        }),
      ),
    );
    const base = hasObjectShape(schema) ? guardFor(stripOneOf(schema), valueExpr, variantKeys) : null;
    const variants = schema.oneOf.map(s => guardFor(resolveRef(s), valueExpr));
    const unionCheck = variants.map(v => `(${v})`).join(" || ");
    if (base && base !== "true") {
      return `(${base}) && (${unionCheck})`;
    }
    return `(${unionCheck})`;
  }
  if (schema.enum) {
    return `(${schema.enum.map(v => `${valueExpr} === ${JSON.stringify(v)}`).join(" || ")})`;
  }
  if ("const" in schema) {
    return `${valueExpr} === ${JSON.stringify(schema.const)}`;
  }
  const type = schema.type;
  if (type === "integer") {
    const min = schema.minimum !== undefined ? `${valueExpr} >= ${schema.minimum}` : "true";
    const max = schema.maximum !== undefined ? `${valueExpr} <= ${schema.maximum}` : "true";
    return `(typeof ${valueExpr} === "number" && Number.isInteger(${valueExpr}) && ${min} && ${max})`;
  }
  if (type === "number") {
    const min = schema.minimum !== undefined ? `${valueExpr} >= ${schema.minimum}` : "true";
    const max = schema.maximum !== undefined ? `${valueExpr} <= ${schema.maximum}` : "true";
    return `(typeof ${valueExpr} === "number" && Number.isFinite(${valueExpr}) && ${min} && ${max})`;
  }
  if (type === "string") {
    return `typeof ${valueExpr} === "string"`;
  }
  if (type === "boolean") {
    return `typeof ${valueExpr} === "boolean"`;
  }
  if (type === "array") {
    const itemCheck = guardFor(resolveRef(schema.items ?? {}), "item");
    const min = schema.minItems !== undefined ? `${valueExpr}.length >= ${schema.minItems}` : "true";
    const max = schema.maxItems !== undefined ? `${valueExpr}.length <= ${schema.maxItems}` : "true";
    return `(Array.isArray(${valueExpr}) && ${min} && ${max} && ${valueExpr}.every(item => ${itemCheck}))`;
  }
  if (type === "object" || schema.properties || schema.additionalProperties !== undefined) {
    const props = schema.properties ?? {};
    const required = new Set(schema.required ?? []);
    const checks = [`isPlainObject(${valueExpr})`];
    const allowedKeys = Array.from(new Set([...Object.keys(props), ...extraKeys]));
    for (const [propName, propSchema] of Object.entries(props)) {
      const propAccess = `${valueExpr}[${JSON.stringify(propName)}]`;
      const check = guardFor(resolveRef(propSchema), propAccess);
      if (required.has(propName)) {
        checks.push(`(${JSON.stringify(propName)} in ${valueExpr} && ${check})`);
      } else {
        checks.push(`(${JSON.stringify(propName)} in ${valueExpr} ? ${check} : true)`);
      }
    }
    if (schema.additionalProperties === false) {
      checks.push(`hasOnlyKeys(${valueExpr}, ${JSON.stringify(allowedKeys)})`);
    } else if (schema.additionalProperties && schema.additionalProperties !== true) {
      const extraGuard = guardFor(resolveRef(schema.additionalProperties), `${valueExpr}[key]`);
      checks.push(`Object.keys(${valueExpr}).every(key => ${JSON.stringify(allowedKeys)}.includes(key) || ${extraGuard})`);
    }
    return checks.join(" && ");
  }
  return "true";
}

function resolveRef(schema) {
  if (schema && typeof schema === "object" && "$ref" in schema) {
    const name = refName(schema.$ref);
    const resolved = schemas[name];
    if (!resolved) {
      throw new Error(`Unresolved $ref ${schema.$ref}`);
    }
    return resolved;
  }
  return schema;
}

const header = `// Generated from midi2.full.openapi.json via scripts/generate-openapi-types.mjs.\n// Do not edit by hand.\n/* eslint-disable */\n\n`;
const helpers = `type UnknownRecord = Record<string, unknown>;\n\nfunction isPlainObject(value: unknown): value is UnknownRecord {\n  return typeof value === \"object\" && value !== null && !Array.isArray(value);\n}\n\nfunction hasOnlyKeys(value: UnknownRecord, keys: string[]): boolean {\n  return Object.keys(value).every(k => keys.includes(k));\n}\n\n`;

const typeEntries = [];
const guardEntries = [];

for (const [rawName, schema] of Object.entries(schemas).sort((a, b) => a[0].localeCompare(b[0]))) {
  const name = sanitizeName(rawName);
  const description = schema.description ? `// ${schema.description}\n` : "";
  const typeDef = `export type ${name} = ${schemaToType(schema)};\n`;
  const guardDef = `export function is${name}(value: unknown): value is ${name} {\n  return ${guardFor(schema, "value")};\n}\n`;
  typeEntries.push(`${description}${typeDef}`);
  guardEntries.push(guardDef);
}

const fileContents = header + helpers + typeEntries.join("\n") + "\n" + guardEntries.join("\n");
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, fileContents);
console.log(`Generated ${outputPath}`);
