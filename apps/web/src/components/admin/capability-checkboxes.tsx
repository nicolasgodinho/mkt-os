import { CAPABILITY_LABELS, type Capability } from '@/lib/identity/capabilities';

/** Extra capabilities granted on top of a role, as a checkbox group named `capabilities`. */
export function CapabilityCheckboxes({
  id,
  legend,
  options,
  checked = [],
}: {
  id: string;
  legend: string;
  options: readonly Capability[];
  checked?: readonly Capability[];
}) {
  return (
    <fieldset className="flex flex-col gap-1.5">
      <legend className="text-sm font-medium">{legend}</legend>
      <div className="flex flex-wrap gap-x-4 gap-y-1">
        {options.map((capability) => (
          <label
            key={capability}
            htmlFor={`${id}-${capability}`}
            className="flex items-center gap-1.5 text-sm"
          >
            <input
              id={`${id}-${capability}`}
              type="checkbox"
              name="capabilities"
              value={capability}
              defaultChecked={checked.includes(capability)}
            />
            {CAPABILITY_LABELS[capability]}
          </label>
        ))}
      </div>
    </fieldset>
  );
}
