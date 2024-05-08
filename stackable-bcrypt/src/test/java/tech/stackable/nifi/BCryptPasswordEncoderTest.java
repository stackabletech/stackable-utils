package tech.stackable.nifi;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class BCryptPasswordEncoderTest {

    // A very simple test case that stores a hashed password that is known to be working with NiFi,
    // which is currently the only use case for this library.
    // This is pretty much just a canary test that should hopefully fail in case later versions of the
    // bcrypt library begin suffering the same issues that we had with other implementations which were
    // incompatible with NiFis hashing implementation.
    @Test
    void test_created_hash() {
        String clearText = "thisisaverysecurepassword!oneeleven!!11";
        String knownCiphertext = "$2b$12$E4CXEUTMBq6rO0qv.1LCcu/5Mui0D6lyIXeRh22z1x9dJTPhMk1MW";
        BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();
        assertTrue(encoder.matches(clearText.toCharArray(), knownCiphertext));
    }
}