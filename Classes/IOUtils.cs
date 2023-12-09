using System.Text.RegularExpressions;

namespace ScaleRESTService;

public class IOUtils
{
    public static byte[] HexToByteArray(string hex)
    {
        return Enumerable.Range(0, hex.Length)
            .Where(x => x % 2 == 0)
            .Select(x => Convert.ToByte(hex.Substring(x, 2), 16))
            .ToArray();
    }

    public static string Substring(string input, int? startIndex = null, int? length = null)
    {
        startIndex ??= 0;
        
        if (startIndex < 0)
        {
            startIndex = input.Length + startIndex;
        }

        if (length == null)
        {
            length = input.Length - startIndex;
        }

        if (startIndex + length > input.Length)
        {
            length = Math.Max(input.Length - (startIndex ?? 0), 0);
        }

        return input.Substring(startIndex ?? 0, length ?? 0);
    }

    /**
     * Translate placeholders of nonvisible characters back to their original form.
     */
    public static string TranslateNonvisibleCharacterPlaceholdersBack(string input)
    {
        if (string.IsNullOrEmpty(input))
        {
            return input;
        }

        string result = "";
        for(int i = 0; i < input.Length; i++)
        {
            if (Substring(input, i, 2) == "\\n")
            {
                result += '\n';
                i++;
            }
            else if (Substring(input, i, 2) == "\\r")
            {
                result += '\r';
                i++;
            }
            else if (Substring(input, i, 2) == "\\t")
            {
                result += '\t';
                i++;
            }
            else if (Substring(input, i, 2) == "\\e")
            {
                result += '\x1B';
                i++;
            }
            else
            {
                var regexResult = Regex.Match(Substring(input, i, 4), @"^\\x([0-9A-Fa-f]{2})");
                if (regexResult.Success)
                {
                    int value = Convert.ToInt32(regexResult.Groups[1].Value, 16);
                    result += ((char)value).ToString();
                    i += 3;
                }
                else
                {
                    result += input[i];
                }
            }
        }
        
        return result;
    }

    public static string FormatNonvisibleCharacters(string input)
    {
        string result = "";
        foreach (char chr in input)
        {
            result += char.IsControl(chr) switch
            {
                false => chr,
                true => chr switch
                {
                    '\n' => "\\n",
                    '\r' => "\\r",
                    '\t' => "\\t", 
                    '\x1B' => "\\e",
                    _ => $"\\x{Convert.ToByte(chr):X2}"
                }
            };
        }
        return Regex.Replace(result, "[^\\x20-\\x7E]", "?");
    }
}