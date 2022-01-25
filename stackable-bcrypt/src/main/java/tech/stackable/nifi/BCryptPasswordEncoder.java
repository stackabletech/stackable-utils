package tech.stackable.nifi;

import at.favre.lib.crypto.bcrypt.BCrypt;
import at.favre.lib.crypto.bcrypt.BCrypt.Hasher;
import at.favre.lib.crypto.bcrypt.BCrypt.Result;
import at.favre.lib.crypto.bcrypt.BCrypt.Verifyer;
import at.favre.lib.crypto.bcrypt.BCrypt.Version;

public class BCryptPasswordEncoder {
    private static final int DEFAULT_COST = 12;
    private static final Version BCRYPT_VERSION;
    private static final Hasher HASHER;
    private static final Verifyer VERIFYER;

    public BCryptPasswordEncoder() {
    }

    public String encode(char[] password) {
        return HASHER.hashToString(12, password);
    }

    public boolean matches(char[] password, String encodedPassword) {
        Result result = VERIFYER.verifyStrict(password, encodedPassword.toCharArray());
        return result.verified;
    }

    static {
        BCRYPT_VERSION = Version.VERSION_2B;
        HASHER = BCrypt.with(BCRYPT_VERSION);
        VERIFYER = BCrypt.verifyer(BCRYPT_VERSION);
    }
}