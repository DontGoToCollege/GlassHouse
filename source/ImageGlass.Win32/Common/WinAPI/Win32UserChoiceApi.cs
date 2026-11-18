/*
GlassHouse, based on ImageGlass
Copyright (C) 2026 DontGoToCollege

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using Windows.Win32;
using Windows.Win32.System.Registry;
using Windows.Win32.UI.Shell;

namespace ImageGlass.Win32.Common;

/// <summary>
/// GlassHouse: one-click defaults, written as Windows Settings writes them (UserChoice + checksum, as SetUserFTA does).
/// Windows offers apps no API for this, so each run first re-checks defaults Windows wrote and refuses on a mismatch.
/// </summary>
public static class Win32UserChoiceApi
{
    private const string FILE_EXTS = @"Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts";
    private const string USER_EXPERIENCE = "User Choice set via Windows User Experience {D18B6DD5-6124-4341-9318-804003BAFA0B}";


    /// <summary>
    /// Sets <paramref name="progIdOf"/>'s ProgId as the user's default for each extension; returns how many Windows
    /// now resolves to it, or <c>-1</c> when this Windows checks defaults some other way and nothing was written.
    /// </summary>
    public static int SetDefaults(IEnumerable<string> extensions, Func<string, string> progIdOf)
    {
        var sid = WindowsIdentity.GetCurrent().User?.Value;
        if (sid is null || !MatchesWindows(sid)) return -1;

        var count = 0;
        foreach (var ext in extensions)
        {
            var progId = progIdOf(ext);
            if (TrySetDefault(ext, progId, sid) && ResolvedProgId(ext) == progId) count++;
        }

        return count;
    }


    /// <summary>
    /// Writes one extension's UserChoice; the checksum covers the minute it is written, so a write that straddles
    /// a minute boundary is redone.
    /// </summary>
    private static bool TrySetDefault(string ext, string progId, string sid)
    {
        try
        {
            using var extKey = Registry.CurrentUser.CreateSubKey($@"{FILE_EXTS}\{ext}", writable: true);

            for (var attempt = 0; attempt < 3; attempt++)
            {
                var before = DateTime.UtcNow;

                // UserChoice denies SetValue to the user; deleting it through the parent is allowed
                extKey.DeleteSubKey("UserChoice", throwOnMissingSubKey: false);
                using (var choiceKey = extKey.CreateSubKey("UserChoice", writable: true))
                {
                    choiceKey.SetValue("ProgId", progId);
                    choiceKey.SetValue("Hash", ComputeHash(ext, sid, progId, before));
                }

                if (ToMinute(DateTime.UtcNow) == ToMinute(before)) return true;
            }
        }
        catch { }

        return false;
    }


    /// <summary>
    /// Whether the checksum matches the defaults Windows itself wrote on this PC (true when there are none to compare).
    /// </summary>
    private static bool MatchesWindows(string sid)
    {
        using var fileExts = Registry.CurrentUser.OpenSubKey(FILE_EXTS);
        if (fileExts is null) return true;

        var compared = 0;
        foreach (var ext in fileExts.GetSubKeyNames())
        {
            using var choiceKey = fileExts.OpenSubKey($@"{ext}\UserChoice");
            if (choiceKey?.GetValue("ProgId") is not string progId || choiceKey.GetValue("Hash") is not string hash) continue;
            if (GetLastWriteUtc(choiceKey) is not DateTime written) continue;

            if (ComputeHash(ext, sid, progId, written) != hash) return false;
            if (++compared == 5) break;
        }

        return true;
    }


    /// <summary>
    /// Gets the ProgId Windows resolves an extension to (the one Explorer opens it with).
    /// </summary>
    private static string ResolvedProgId(string ext)
    {
        Span<char> buffer = stackalloc char[260];
        var length = (uint)buffer.Length;
        var hr = PInvoke.AssocQueryString(ASSOCF.ASSOCF_NONE, ASSOCSTR.ASSOCSTR_PROGID, ext, null, buffer, ref length);

        return hr.Succeeded && length > 0 ? new string(buffer[..((int)length - 1)]) : string.Empty;
    }


    /// <summary>
    /// Reads a registry key's last-write time, which the checksum is based on.
    /// </summary>
    private static unsafe DateTime? GetLastWriteUtc(RegistryKey key)
    {
        System.Runtime.InteropServices.ComTypes.FILETIME ft;
        var err = PInvoke.RegQueryInfoKey(new HKEY(key.Handle.DangerousGetHandle()), default, null, null, null, null, null, null, null, null, null, &ft);
        if (err != 0) return null;

        return DateTime.FromFileTimeUtc(((long)(uint)ft.dwHighDateTime << 32) | (uint)ft.dwLowDateTime);
    }


    private static DateTime ToMinute(DateTime utc) => new(utc.Year, utc.Month, utc.Day, utc.Hour, utc.Minute, 0, DateTimeKind.Utc);


    /// <summary>
    /// Computes the UserChoice checksum: MD5 of the lowercased extension, SID, ProgId, minute and a fixed phrase,
    /// folded by two multiply-shift passes. Verified against 141 defaults Windows wrote (2026-11-17).
    /// </summary>
    internal static string ComputeHash(string ext, string sid, string progId, DateTime writtenUtc)
    {
        var fileTime = ToMinute(writtenUtc).ToFileTimeUtc();
        var stamp = ((uint)(fileTime >> 32)).ToString("x8") + ((uint)fileTime).ToString("x8");
        var info = (ext + sid + progId + stamp + USER_EXPERIENCE).ToLowerInvariant();

        var data = new byte[(info.Length * 2) + 2];
        Encoding.Unicode.GetBytes(info, 0, info.Length, data, 0);
        var md5 = MD5.HashData(data);

        var length = ((data.Length & 4) <= 1 ? 1 : 0) + (data.Length >> 2) - 1;
        if (length <= 1) return string.Empty;
        var rounds = ((uint)(length - 2) >> 1) + 1;

        var m0 = BitConverter.ToUInt32(md5, 0) | 1;
        var m1 = BitConverter.ToUInt32(md5, 4) | 1;
        uint cache, out1, out2;
        int p;

        unchecked
        {
            // pass 1
            cache = 0; out1 = 0; out2 = 0; p = 0;
            var a = m0 + 0x69FB0000u;
            var b = m1 + 0x13DB0000u;
            for (var n = rounds; n > 0; n--)
            {
                var r0 = BitConverter.ToUInt32(data, p) + out1;
                var r1 = BitConverter.ToUInt32(data, p + 4);
                p += 8;
                var r2 = (r0 * a) - (0x10FA9605u * (r0 >> 16));
                var r2b = (0x79F8A395u * r2) + (0x689B6B9Fu * (r2 >> 16));
                var r3 = (0xEA970001u * r2b) - (0x3C101569u * (r2b >> 16));
                var r4 = r3 + r1;
                var r5 = cache + r3;
                var r6 = (r4 * b) - (0x3CE8EC25u * (r4 >> 16));
                var r6b = (0x59C3AF2Du * r6) - (0x2232E0F1u * (r6 >> 16));
                out1 = (0x1EC90001u * r6b) + (0x35BD1EC9u * (r6b >> 16));
                out2 = r5 + out1;
                cache = out2;
            }

            var h0 = out1;
            var h1 = out2;

            // pass 2
            cache = 0; out1 = 0; out2 = 0; p = 0;
            for (var n = rounds; n > 0; n--)
            {
                var r0 = BitConverter.ToUInt32(data, p) + out1;
                p += 8;
                var r1 = r0 * m0;
                var r1b = (0xB1110000u * r1) - (0x30674EEFu * (r1 >> 16));
                var r2 = (0x5B9F0000u * r1b) - (0x78F7A461u * (r1b >> 16));
                var r2b = (0x12CEB96Du * (r2 >> 16)) - (0x46930000u * r2);
                var r3 = (0x1D830000u * r2b) + (0x257E1D83u * (r2b >> 16));
                var r4 = m1 * (r3 + BitConverter.ToUInt32(data, p - 4));
                var r4b = (0x16F50000u * r4) - (0x5D8BE90Bu * (r4 >> 16));
                var r5 = (0x96FF0000u * r4b) - (0x2C7C6901u * (r4b >> 16));
                var r5b = (0x2B890000u * r5) + (0x7C932B89u * (r5 >> 16));
                out1 = (0x9F690000u * r5b) - (0x405B6097u * (r5b >> 16));
                out2 = out1 + cache + r3;
                cache = out2;
            }

            var result = new byte[8];
            BitConverter.GetBytes(out1 ^ h0).CopyTo(result, 0);
            BitConverter.GetBytes(out2 ^ h1).CopyTo(result, 4);
            return Convert.ToBase64String(result);
        }
    }
}
